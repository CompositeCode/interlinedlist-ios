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

    func prefetchAll(userId: String?) async {
        if let uid = userId, self.userId != uid {
            self.userId = uid
            await loadFromCache(userId: uid)
        }
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.refreshFeed() }
            group.addTask { await self.refreshLists() }
            group.addTask { await self.refreshDocuments() }
            group.addTask { await self.refreshCounts() }
        }
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
        do {
            let delta = try await APIClient.shared.documentSync(lastSyncAt: docSyncCursor)
            let current = DocumentSyncState(folders: documentFolders, documents: documents, lastSyncAt: docSyncCursor)
            let merged = DocumentSyncMerge.apply(delta: delta, to: current)
            documentFolders = merged.folders
            documents = merged.documents
            docSyncCursor = merged.lastSyncAt
            saveDocsSyncCache()
        } catch APIError.status(401) {
        } catch APIError.status(429) {
            // Rate limited — keep cached state and skip this cycle.
        } catch {
            if documents.isEmpty && documentFolders.isEmpty {
                documentsError = "Failed to load documents."
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

    // MARK: - Optimistic mutations

    func insertFeedMessage(_ message: Message) {
        feedMessages.insert(message, at: 0)
        saveFeedCache()
    }

    func removeList(id: String) { userLists.removeAll { $0.id == id }; saveListsCache() }
    func removeListFolder(id: String) { listFolders.removeAll { $0.id == id }; saveListsCache() }

    func insertDocument(_ doc: Document) { documents.insert(doc, at: 0); persistDocs() }
    func updateDocument(_ doc: Document) {
        if let idx = documents.firstIndex(where: { $0.id == doc.id }) { documents[idx] = doc }
        persistDocs()
    }
    func removeDocument(id: String) { documents.removeAll { $0.id == id }; persistDocs() }
    func insertDocumentFolder(_ folder: DocumentFolder) { documentFolders.append(folder); persistDocs() }
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
        let snapshot = DocumentSyncState(folders: documentFolders, documents: documents, lastSyncAt: docSyncCursor)
        Task { await cache.save(snapshot, key: "\(uid)_docsync") }
    }
}

private struct ListsCache: Codable {
    let folders: [ListFolder]
    let lists: [UserList]
}

private struct DocsCache: Codable {
    let folders: [DocumentFolder]
    let documents: [Document]
}
