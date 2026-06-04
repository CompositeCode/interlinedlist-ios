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

    private let cache = DataCache.shared
    private var userId: String?

    func prefetchAll(userId: String?) async {
        if let uid = userId, self.userId != uid {
            self.userId = uid
            loadFromCache(userId: uid)
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
        if feedMessages.isEmpty { loadFromCache(userId: id) }
        saveToCache()
    }

    func refreshFeed() async {
        feedLoading = feedMessages.isEmpty
        feedError = nil
        defer { feedLoading = false }
        do {
            let (list, _) = try await APIClient.shared.messages(limit: 50, offset: 0, onlyMine: false, tag: nil)
            feedMessages = list
            saveToCache()
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
            saveToCache()
        } catch APIError.status(401) {
        } catch APIError.server(let msg) {
            if userLists.isEmpty { listsError = msg }
        } catch {
            if userLists.isEmpty { listsError = error.localizedDescription }
        }
    }

    func refreshDocuments() async {
        documentsLoading = documents.isEmpty
        documentsError = nil
        defer { documentsLoading = false }
        do {
            async let fTask = APIClient.shared.documentFolders()
            async let dTask = APIClient.shared.documents()
            let (f, d) = try await (fTask, dTask)
            documentFolders = f
            documents = d
            saveToCache()
        } catch APIError.status(401) {
        } catch APIError.status(403) {
            documentsError = "Requires active subscription."
        } catch {
            if documents.isEmpty { documentsError = "Failed to load documents." }
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
        }
    }

    // MARK: - Optimistic mutations

    func removeList(id: String) { userLists.removeAll { $0.id == id }; saveToCache() }
    func removeListFolder(id: String) { listFolders.removeAll { $0.id == id }; saveToCache() }

    func insertDocument(_ doc: Document) { documents.insert(doc, at: 0); saveToCache() }
    func updateDocument(_ doc: Document) {
        if let idx = documents.firstIndex(where: { $0.id == doc.id }) { documents[idx] = doc }
        saveToCache()
    }
    func removeDocument(id: String) { documents.removeAll { $0.id == id }; saveToCache() }
    func insertDocumentFolder(_ folder: DocumentFolder) { documentFolders.append(folder); saveToCache() }

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
        userId = nil
    }

    // MARK: - Cache

    private func loadFromCache(userId: String) {
        if let msgs: [Message] = cache.load(key: "\(userId)_feed") { feedMessages = msgs }
        if let cached: ListsCache = cache.load(key: "\(userId)_lists") {
            listFolders = cached.folders
            userLists = cached.lists
        }
        if let cached: DocsCache = cache.load(key: "\(userId)_docs") {
            documentFolders = cached.folders
            documents = cached.documents
        }
    }

    private func saveToCache() {
        guard let uid = userId else { return }
        cache.save(feedMessages, key: "\(uid)_feed")
        cache.save(ListsCache(folders: listFolders, lists: userLists), key: "\(uid)_lists")
        cache.save(DocsCache(folders: documentFolders, documents: documents), key: "\(uid)_docs")
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
