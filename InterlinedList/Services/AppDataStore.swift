//
//  AppDataStore.swift
//  InterlinedList
//

import Foundation

@MainActor
final class AppDataStore: ObservableObject {
    @Published private(set) var feedMessages: [Message] = []
    @Published private(set) var feedLoading = true
    @Published private(set) var feedError: String?

    @Published private(set) var listFolders: [ListFolder] = []
    @Published private(set) var userLists: [UserList] = []
    @Published private(set) var listsLoading = true
    @Published private(set) var listsError: String?

    @Published private(set) var documentFolders: [DocumentFolder] = []
    @Published private(set) var documents: [Document] = []
    @Published private(set) var documentsLoading = true
    @Published private(set) var documentsError: String?

    @Published private(set) var unreadCount = 0
    @Published private(set) var pendingRequestCount = 0
    @Published private(set) var dmUnreadCount = 0

    private let cache = DataCache()
    private var userId: String?

    /// Narrow API surface for the offline document sync cycle (push + pull), so
    /// the store can be unit-tested with a mock without touching the singleton's
    /// feed/lists/counts paths. Defaults to `APIClient.shared`.
    private let syncAPI: DocumentSyncAPI

    init(syncAPI: DocumentSyncAPI = APIClient.shared) {
        self.syncAPI = syncAPI
    }

    /// G9 Slice 1. When true, documents load from a persisted `DocumentSyncState`
    /// and refresh via `GET /api/documents/sync` (delta pull + tombstones) instead
    /// of `GET /api/documents` + `documentFolders()`. Defaults true — one call
    /// returns the whole tree vs. the root-only documents endpoint. Overridable
    /// via Info.plist key `ILOfflineDocSync` (set to NO to keep the online path).
    private let offlineDocSyncEnabled: Bool = {
        if let flag = Bundle.main.infoDictionary?["ILOfflineDocSync"] as? Bool {
            return flag
        }
        if let str = Bundle.main.infoDictionary?["ILOfflineDocSync"] as? String {
            return (str as NSString).boolValue
        }
        return true
    }()

    private var docSyncCursor: String?

    /// Slice 2 offline write path. Pending create/update/delete ops (coalesced
    /// one-per-id) and the per-id local sync state, persisted alongside the
    /// documents so edits survive an app restart while offline.
    private var docSyncOutbox: [SyncOperation] = []
    private var docLocalStates: [String: LocalSyncState] = [:]

    /// Slice 3 baselines: per-doc server `updatedAt` at the last point the doc was
    /// `.synced`. Conflict detection compares a pull row's `updatedAt` to this.
    private var docBaselines: [String: String] = [:]

    /// Ids of documents with un-pushed edits — drives the optional "pending sync"
    /// affordance in the UI.
    @Published private(set) var pendingSyncDocIds: Set<String> = []

    /// Slice 3. Documents edited elsewhere while we held un-pushed local edits;
    /// their server version was kept as a conflict copy. Drives a dismissible
    /// banner in `DocumentsView`. Empty when there are no unresolved conflicts.
    @Published private(set) var syncConflicts: [SyncConflictNotice] = []

    func dismissSyncConflicts() { syncConflicts = [] }

    private var reachability: NetworkReachability?
    private var pushInFlight = false
    private var pushRequested = false

    func prefetchAll(userId: String?) async {
        if let uid = userId, self.userId != uid {
            self.userId = uid
            await loadFromCache(userId: uid)
        }
        startReachabilityIfNeeded()
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.refreshFeed() }
            group.addTask { await self.refreshLists() }
            group.addTask { await self.refreshDocuments() }
            group.addTask { await self.refreshCounts() }
        }
    }

    private func startReachabilityIfNeeded() {
        guard offlineDocSyncEnabled, reachability == nil else { return }
        let monitor = NetworkReachability()
        monitor.start { [weak self] in
            Task { @MainActor [weak self] in await self?.pushOutbox() }
        }
        reachability = monitor
    }

    func onUserIdAvailable(_ id: String) {
        guard userId != id else { return }
        userId = id
        if feedMessages.isEmpty {
            Task { await loadFromCache(userId: id) }
        }
    }

    func refreshFeed() async {
        feedLoading = feedMessages.isEmpty
        feedError = nil
        defer { feedLoading = false }
        do {
            let (list, _) = try await APIClient.shared.messages(limit: 50, offset: 0, onlyMine: false, tag: nil)
            feedMessages = list
            saveFeedCache()
        } catch APIError.status(401) {
        } catch APIError.server(let msg) {
            if feedMessages.isEmpty { feedError = msg }
        } catch {
            if feedMessages.isEmpty { feedError = "Connection failed. Please try again." }
        }
    }

    func refreshLists() async {
        listsLoading = userLists.isEmpty
        listsError = nil
        defer { listsLoading = false }
        do {
            let result = try await APIClient.shared.listsAndFolders()
            listFolders = result.folders
            userLists = result.lists
            saveListsCache()
        } catch APIError.status(401) {
        } catch APIError.server(let msg) {
            if userLists.isEmpty { listsError = msg }
        } catch {
            if userLists.isEmpty { listsError = error.localizedDescription }
        }
    }

    func refreshDocuments() async {
        if offlineDocSyncEnabled {
            await refreshDocumentsViaSync()
            return
        }
        documentsLoading = documents.isEmpty
        documentsError = nil
        defer { documentsLoading = false }
        do {
            async let fTask = APIClient.shared.documentFolders()
            async let dTask = APIClient.shared.documents()
            let (f, d) = try await (fTask, dTask)
            documentFolders = f
            documents = d
            saveDocsCache()
        } catch APIError.status(401) {
        } catch {
            // GET /api/documents is not documented as subscriber-only, so a
            // 403 here would be an unexpected case. Surface it as a generic
            // load failure rather than subscription copy.
            if documents.isEmpty { documentsError = "Failed to load documents." }
        }
    }

    private func refreshDocumentsViaSync() async {
        documentsLoading = documents.isEmpty
        documentsError = nil
        defer { documentsLoading = false }
        await syncCycle()
    }

    /// One sync cycle (Slice 3, **pull-first**): pull the delta, detect and
    /// resolve conflicts (conflict-copy), merge while protecting the conflicting
    /// dirty docs, **then** push the outbox (local edits + new conflict copies).
    /// Pull-first is required so the server's newer version is seen and preserved
    /// *before* a local push (which is last-writer-wins) could clobber it.
    /// Serialized via `pushInFlight` so overlapping triggers (foreground +
    /// reconnect + edit) don't overlap.
    private func syncCycle() async {
        guard offlineDocSyncEnabled else { return }
        if pushInFlight {
            pushRequested = true
            return
        }
        pushInFlight = true
        defer {
            pushInFlight = false
            if pushRequested {
                pushRequested = false
                Task { await syncCycle() }
            }
        }
        await pullDocuments()
        await drainOutbox()
    }

    /// Trigger point exposed to the app (foreground / reconnect / after a local
    /// edit). Runs a full pull-then-push cycle.
    func pushOutbox() async {
        await syncCycle()
    }

    private func pullDocuments() async {
        do {
            let delta = try await syncAPI.documentSync(lastSyncAt: docSyncCursor)
            var state = currentSyncState()

            let conflicts = DocumentSyncConflict.detectConflicts(
                delta: delta, dirtyIds: state.dirtyIds, baselines: state.baselines)
            resolveConflicts(conflicts, into: &state)

            let protectedIds = Set(conflicts.map { $0.id })
            let merged = DocumentSyncMerge.apply(delta: delta, to: state, protectingIds: protectedIds)
            state.folders = merged.folders
            state.documents = merged.documents
            state.lastSyncAt = merged.lastSyncAt

            recordBaselines(from: delta, protectedIds: protectedIds, into: &state)

            applySyncState(state)
            saveDocsSyncCache()
        } catch APIError.status(401) {
        } catch APIError.status(429) {
            // Rate limited — keep cached state and skip this cycle.
        } catch APIError.rateLimited {
            // Rate limited — keep cached state and skip this cycle.
        } catch {
            if documents.isEmpty && documentFolders.isEmpty {
                documentsError = "Failed to load documents."
            }
        }
    }

    /// For each conflict, keep the local (dirty) doc live and preserve the SERVER
    /// version as a new conflict-copy document: insert it, enqueue its `create`
    /// op, and record a banner notice. Real `Date()`/`UUID()` live here; the pure
    /// shape is built by `DocumentSyncConflict`.
    private func resolveConflicts(_ conflicts: [ConflictInfo], into state: inout DocumentSyncState) {
        guard !conflicts.isEmpty else { return }
        let now = Date()
        var notices: [SyncConflictNotice] = []
        for conflict in conflicts {
            let copy = DocumentSyncConflict.makeConflictCopy(
                server: conflict.serverDocument, date: now, newId: UUID().uuidString)
            if !state.documents.contains(where: { $0.id == copy.document.id }) {
                state.documents.insert(copy.document, at: 0)
            }
            DocumentSyncOutbox.enqueue(copy.operation, into: &state)
            let liveTitle = state.documents.first { $0.id == conflict.id }?.title
                ?? conflict.serverDocument.title
            notices.append(SyncConflictNotice(id: conflict.id,
                                              originalTitle: liveTitle,
                                              copyTitle: copy.document.title))
        }
        syncConflicts.append(contentsOf: notices)
    }

    /// After a pull, baseline every delta document (conflicting or not) at the
    /// server `updatedAt` we just saw. Non-conflicting rows were merged in;
    /// conflicting rows kept their local copy live but we advance their baseline
    /// to the now-seen server version so the *same* server edit isn't detected as
    /// a conflict twice (only a genuinely newer server edit re-triggers). Deletes
    /// drop the baseline.
    private func recordBaselines(from delta: DocumentSyncResponse,
                                 protectedIds: Set<String>,
                                 into state: inout DocumentSyncState) {
        for document in delta.documents {
            if document.deletedAt != nil {
                if !protectedIds.contains(document.id) {
                    state.baselines[document.id] = nil
                }
            } else if let updatedAt = document.updatedAt {
                state.baselines[document.id] = updatedAt
            }
        }
    }

    private func drainOutbox() async {
        guard !docSyncOutbox.isEmpty else { return }
        let payload = docSyncOutbox
        do {
            let cursor = try await syncAPI.pushDocumentSync(operations: payload)
            var state = currentSyncState()
            DocumentSyncOutbox.clearOutbox(payload, from: &state)
            state.lastSyncAt = cursor
            recordPushBaselines(payload, cursor: cursor, into: &state)
            applySyncState(state)
            saveDocsSyncCache()
        } catch APIError.status(401) {
            // Auth is handled elsewhere; keep the outbox for replay.
        } catch APIError.rateLimited {
            // Back off: keep the outbox and skip the pull this cycle.
        } catch {
            // Offline / server error: keep the outbox for the next trigger.
        }
    }

    /// After a successful push, baseline each pushed create/update at the push
    /// cursor (the server's post-push `updatedAt` for those rows) and drop the
    /// baseline for deletes. Keeps conflict detection accurate on the next pull.
    private func recordPushBaselines(_ pushed: [SyncOperation], cursor: String,
                                     into state: inout DocumentSyncState) {
        for op in pushed {
            switch op.op {
            case .create, .update:
                state.baselines[op.data.id] = cursor
            case .delete:
                state.baselines[op.data.id] = nil
            }
        }
    }

    func refreshCounts() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                if let response = try? await APIClient.shared.notifications() {
                    await MainActor.run { self.unreadCount = response.unreadCount }
                }
            }
            group.addTask {
                if let requests = try? await APIClient.shared.followRequests() {
                    await MainActor.run { self.pendingRequestCount = requests.count }
                }
            }
            group.addTask {
                if let count = try? await APIClient.shared.dmUnreadCount() {
                    await MainActor.run { self.dmUnreadCount = count }
                }
            }
        }
    }

    func refreshDMUnread() async {
        if let count = try? await APIClient.shared.dmUnreadCount() {
            dmUnreadCount = count
        }
    }

    // MARK: - Offline-aware document mutations (Slice 2)

    /// True when writes should route through the outbox rather than the online
    /// document endpoints. Views branch on this to keep the flag-OFF path byte-for-byte.
    var offlineDocumentWritesEnabled: Bool { offlineDocSyncEnabled }

    /// Applies a create optimistically to `documents`, enqueues a `create` op, and
    /// triggers a push. Returns the client-synthesized `Document` (with a
    /// client-generated `id`) for the UI to navigate to. Flag-ON only.
    func createDocumentOffline(title: String, content: String?, isPublic: Bool, folderId: String?) -> Document {
        let normalizedFolderId = (folderId?.isEmpty == true) ? nil : folderId
        let now = ISO8601DateFormatter().string(from: Date())
        let doc = Document(id: UUID().uuidString, title: title, content: content,
                           folderId: normalizedFolderId, isPublic: isPublic,
                           createdAt: now, updatedAt: now)
        documents.insert(doc, at: 0)
        enqueue(SyncOperation(op: .create, type: .document,
                              data: SyncOpData(id: doc.id, folderId: normalizedFolderId,
                                               title: title, content: content, isPublic: isPublic)))
        return doc
    }

    /// Applies an edit optimistically to `documents` and enqueues an `update` op.
    func updateDocumentOffline(id: String, title: String, content: String?, isPublic: Bool, folderId: String?) -> Document {
        let normalizedFolderId = (folderId?.isEmpty == true) ? nil : folderId
        let now = ISO8601DateFormatter().string(from: Date())
        let existing = documents.first { $0.id == id }
        let updated = Document(id: id, title: title, content: content,
                               folderId: normalizedFolderId, isPublic: isPublic,
                               createdAt: existing?.createdAt, updatedAt: now)
        if let idx = documents.firstIndex(where: { $0.id == id }) {
            documents[idx] = updated
        } else {
            documents.insert(updated, at: 0)
        }
        enqueue(SyncOperation(op: .update, type: .document,
                              data: SyncOpData(id: id, folderId: normalizedFolderId,
                                               title: title, content: content, isPublic: isPublic)))
        return updated
    }

    func deleteDocumentOffline(id: String) {
        documents.removeAll { $0.id == id }
        enqueue(SyncOperation(op: .delete, type: .document, data: SyncOpData(id: id)))
    }

    func createDocumentFolderOffline(name: String, parentId: String?) -> DocumentFolder {
        let normalizedParentId = (parentId?.isEmpty == true) ? nil : parentId
        let now = ISO8601DateFormatter().string(from: Date())
        let folder = DocumentFolder(id: UUID().uuidString, name: name,
                                    parentId: normalizedParentId, updatedAt: now)
        documentFolders.append(folder)
        enqueue(SyncOperation(op: .create, type: .folder,
                              data: SyncOpData(id: folder.id, parentId: normalizedParentId, name: name)))
        return folder
    }

    func deleteDocumentFolderOffline(id: String) {
        // Cascade locally the way the server would (subfolders + docs inside).
        let removedFolderIds = descendantFolderIds(of: id)
        documentFolders.removeAll { removedFolderIds.contains($0.id) }
        documents.removeAll { doc in
            guard let fid = doc.folderId, !fid.isEmpty else { return false }
            return removedFolderIds.contains(fid)
        }
        enqueue(SyncOperation(op: .delete, type: .folder, data: SyncOpData(id: id)))
    }

    private func descendantFolderIds(of rootId: String) -> Set<String> {
        var result: Set<String> = [rootId]
        var changed = true
        while changed {
            changed = false
            for folder in documentFolders {
                if let parent = folder.parentId, result.contains(parent), !result.contains(folder.id) {
                    result.insert(folder.id)
                    changed = true
                }
            }
        }
        return result
    }

    private func enqueue(_ op: SyncOperation) {
        var state = currentSyncState()
        DocumentSyncOutbox.enqueue(op, into: &state)
        applySyncState(state)
        saveDocsSyncCache()
        Task { await debouncedPush() }
    }

    private func debouncedPush() async {
        try? await Task.sleep(nanoseconds: 400_000_000)
        await pushOutbox()
    }

    private func currentSyncState() -> DocumentSyncState {
        DocumentSyncState(folders: documentFolders, documents: documents,
                          lastSyncAt: docSyncCursor, outbox: docSyncOutbox,
                          localStates: docLocalStates, baselines: docBaselines)
    }

    private func applySyncState(_ state: DocumentSyncState) {
        documentFolders = state.folders
        documents = state.documents
        docSyncCursor = state.lastSyncAt
        docSyncOutbox = state.outbox
        docLocalStates = state.localStates
        docBaselines = state.baselines
        pendingSyncDocIds = state.dirtyIds
    }

    // MARK: - Optimistic mutations

    func insertFeedMessage(_ message: Message) {
        feedMessages.insert(message, at: 0)
        saveFeedCache()
    }

    func removeList(id: String) { userLists.removeAll { $0.id == id }; saveListsCache() }
    func removeListFolder(id: String) { listFolders.removeAll { $0.id == id }; saveListsCache() }

    /// Idempotent upsert by id — safe to call after `createDocumentOffline`
    /// (which already inserted the row) so the flag-ON callbacks don't duplicate.
    func insertDocument(_ doc: Document) {
        if let idx = documents.firstIndex(where: { $0.id == doc.id }) {
            documents[idx] = doc
        } else {
            documents.insert(doc, at: 0)
        }
        persistDocs()
    }
    func updateDocument(_ doc: Document) {
        if let idx = documents.firstIndex(where: { $0.id == doc.id }) { documents[idx] = doc }
        persistDocs()
    }
    func removeDocument(id: String) { documents.removeAll { $0.id == id }; persistDocs() }
    func insertDocumentFolder(_ folder: DocumentFolder) {
        if !documentFolders.contains(where: { $0.id == folder.id }) { documentFolders.append(folder) }
        persistDocs()
    }
    func removeDocumentFolder(id: String) { documentFolders.removeAll { $0.id == id }; persistDocs() }

    private func persistDocs() {
        if offlineDocSyncEnabled {
            saveDocsSyncCache()
        } else {
            saveDocsCache()
        }
    }

    func reset() {
        feedMessages = []
        listFolders = []
        userLists = []
        documentFolders = []
        documents = []
        feedLoading = true
        listsLoading = true
        documentsLoading = true
        feedError = nil
        listsError = nil
        documentsError = nil
        unreadCount = 0
        pendingRequestCount = 0
        dmUnreadCount = 0
        docSyncCursor = nil
        docSyncOutbox = []
        docLocalStates = [:]
        docBaselines = [:]
        pendingSyncDocIds = []
        syncConflicts = []
        reachability?.stop()
        reachability = nil
        userId = nil
    }

    // MARK: - Cache

    private func loadFromCache(userId: String) async {
        if let msgs: [Message] = await cache.load(key: "\(userId)_feed") { feedMessages = msgs }
        if let cached: ListsCache = await cache.load(key: "\(userId)_lists") {
            listFolders = cached.folders
            userLists = cached.lists
        }
        if offlineDocSyncEnabled {
            if let state: DocumentSyncState = await cache.load(key: "\(userId)_docsync") {
                documentFolders = state.folders
                documents = state.documents
                docSyncCursor = state.lastSyncAt
                docSyncOutbox = state.outbox
                docLocalStates = state.localStates
                docBaselines = state.baselines
                pendingSyncDocIds = state.dirtyIds
            }
        } else if let cached: DocsCache = await cache.load(key: "\(userId)_docs") {
            documentFolders = cached.folders
            documents = cached.documents
        }
    }

    private func saveFeedCache() {
        guard let uid = userId else { return }
        let snapshot = feedMessages
        Task { await cache.save(snapshot, key: "\(uid)_feed") }
    }

    private func saveListsCache() {
        guard let uid = userId else { return }
        let snapshot = ListsCache(folders: listFolders, lists: userLists)
        Task { await cache.save(snapshot, key: "\(uid)_lists") }
    }

    private func saveDocsCache() {
        guard let uid = userId else { return }
        let snapshot = DocsCache(folders: documentFolders, documents: documents)
        Task { await cache.save(snapshot, key: "\(uid)_docs") }
    }

    private func saveDocsSyncCache() {
        guard let uid = userId else { return }
        let snapshot = currentSyncState()
        Task { await cache.save(snapshot, key: "\(uid)_docsync") }
    }
}

/// The two `/api/documents/sync` calls the offline cycle needs. Kept narrow (ISP)
/// so `AppDataStore` can be tested against a mock without the full `APIClient`.
protocol DocumentSyncAPI {
    func documentSync(lastSyncAt: String?) async throws -> DocumentSyncResponse
    func pushDocumentSync(operations: [SyncOperation]) async throws -> String
}

extension APIClient: DocumentSyncAPI {}

private struct ListsCache: Codable {
    let folders: [ListFolder]
    let lists: [UserList]
}

private struct DocsCache: Codable {
    let folders: [DocumentFolder]
    let documents: [Document]
}
