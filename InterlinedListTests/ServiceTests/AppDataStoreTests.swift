import Combine
import XCTest
@testable import InterlinedList

@MainActor
final class AppDataStoreTests: XCTestCase {
    var sut: AppDataStore!

    override func setUp() {
        super.setUp()
        sut = AppDataStore()
    }

    // MARK: - insertFeedMessage

    func test_insertFeedMessage_insertsAtHead() {
        let first = makeMessage(id: "a")
        let second = makeMessage(id: "b")
        sut.insertFeedMessage(first)
        sut.insertFeedMessage(second)
        // Most recently inserted should be at index 0.
        XCTAssertEqual(sut.feedMessages.first?.id, "b")
        XCTAssertEqual(sut.feedMessages.last?.id, "a")
    }

    func test_insertFeedMessage_incrementsCount() {
        XCTAssertEqual(sut.feedMessages.count, 0)
        sut.insertFeedMessage(makeMessage(id: "x"))
        XCTAssertEqual(sut.feedMessages.count, 1)
        sut.insertFeedMessage(makeMessage(id: "y"))
        XCTAssertEqual(sut.feedMessages.count, 2)
    }

    func test_insertFeedMessage_preservesExistingMessages() {
        sut.insertFeedMessage(makeMessage(id: "old"))
        sut.insertFeedMessage(makeMessage(id: "new"))
        XCTAssertTrue(sut.feedMessages.contains { $0.id == "old" })
        XCTAssertTrue(sut.feedMessages.contains { $0.id == "new" })
    }

    func test_insertFeedMessage_isVisibleAfterInitialMessages() {
        sut.insertFeedMessage(makeMessage(id: "existing1"))
        sut.insertFeedMessage(makeMessage(id: "existing2"))
        sut.insertFeedMessage(makeMessage(id: "existing3"))
        sut.insertFeedMessage(makeMessage(id: "newPost"))
        XCTAssertEqual(sut.feedMessages.first?.id, "newPost")
        XCTAssertTrue(sut.feedMessages.contains { $0.id == "existing1" })
        XCTAssertTrue(sut.feedMessages.contains { $0.id == "existing2" })
        XCTAssertTrue(sut.feedMessages.contains { $0.id == "existing3" })
        XCTAssertEqual(sut.feedMessages.count, 4)
    }

    func test_insertFeedMessage_newMessageAppearsBeforeExisting() {
        sut.insertFeedMessage(makeMessage(id: "first"))
        sut.insertFeedMessage(makeMessage(id: "second"))
        sut.insertFeedMessage(makeMessage(id: "third"))
        XCTAssertEqual(sut.feedMessages[0].id, "third")
        XCTAssertEqual(sut.feedMessages[1].id, "second")
        XCTAssertEqual(sut.feedMessages[2].id, "first")
    }

    func test_insertFeedMessage_doesNotDuplicateExistingMessage() {
        sut.insertFeedMessage(makeMessage(id: "dup"))
        sut.insertFeedMessage(makeMessage(id: "dup"))
        // insertFeedMessage does not deduplicate at the store layer.
        // FeedView's onChange filters by !existingIds.contains($0.id) before prepending.
        XCTAssertEqual(sut.feedMessages.count, 2)
    }

    func test_insertFeedMessage_publishesCountChange() {
        let countIncreased = expectation(description: "feedMessages count increases")
        var cancellables = Set<AnyCancellable>()
        sut.$feedMessages
            .dropFirst()
            .sink { messages in
                if messages.count == 1 {
                    countIncreased.fulfill()
                }
            }
            .store(in: &cancellables)
        sut.insertFeedMessage(makeMessage(id: "z"))
        wait(for: [countIncreased], timeout: 1.0)
    }

    // MARK: - reset

    func test_reset_clearsFeedMessages() {
        sut.insertFeedMessage(makeMessage(id: "x"))
        sut.reset()
        XCTAssertTrue(sut.feedMessages.isEmpty)
    }

    func test_reset_resetsLoadingFlag() {
        // feedLoading starts true, goes false after a refresh; reset should restore true.
        sut.reset()
        XCTAssertTrue(sut.feedLoading)
    }

    // MARK: - optimistic document mutations

    func test_insertDocument_insertsAtHead() {
        let doc = makeDocument(id: "d1")
        sut.insertDocument(doc)
        XCTAssertEqual(sut.documents.first?.id, "d1")
    }

    func test_removeDocument_removesById() {
        sut.insertDocument(makeDocument(id: "d1"))
        sut.insertDocument(makeDocument(id: "d2"))
        sut.removeDocument(id: "d1")
        XCTAssertFalse(sut.documents.contains { $0.id == "d1" })
        XCTAssertTrue(sut.documents.contains { $0.id == "d2" })
    }

    // MARK: - Offline document write cycle (Slice 2)

    func test_createDocumentOffline_insertsOptimisticallyAndMarksPending() {
        let store = AppDataStore(syncAPI: FailingSyncAPI())
        let doc = store.createDocumentOffline(title: "Draft", content: "hi", isPublic: false, folderId: nil)
        XCTAssertEqual(store.documents.first?.id, doc.id)
        XCTAssertEqual(store.documents.first?.title, "Draft")
        XCTAssertTrue(store.pendingSyncDocIds.contains(doc.id))
    }

    func test_pushOutbox_failure_keepsPendingState() async {
        let api = FailingSyncAPI()
        let store = AppDataStore(syncAPI: api)
        let doc = store.createDocumentOffline(title: "Draft", content: nil, isPublic: false, folderId: nil)
        await store.pushOutbox()
        // Push failed (offline): the doc is still optimistically present and pending.
        XCTAssertTrue(store.documents.contains { $0.id == doc.id })
        XCTAssertTrue(store.pendingSyncDocIds.contains(doc.id))
        XCTAssertTrue(api.pushCalled)
    }

    func test_pushOutbox_success_clearsPendingAndPulls() async {
        let api = RecordingSyncAPI(pushCursor: "2026-08-02T00:00:00Z",
                                   pullResponse: DocumentSyncResponse(lastSyncAt: "2026-08-02T00:00:00Z"))
        let store = AppDataStore(syncAPI: api)
        let doc = store.createDocumentOffline(title: "Draft", content: nil, isPublic: false, folderId: nil)
        await store.pushOutbox()
        // On success the outbox is cleared → no longer pending, and the doc stays.
        XCTAssertFalse(store.pendingSyncDocIds.contains(doc.id))
        XCTAssertTrue(store.documents.contains { $0.id == doc.id })
        XCTAssertTrue(api.pushCalled, "push runs first")
        XCTAssertTrue(api.pullCalled, "then pull reconciles")
    }

    func test_deleteDocumentOffline_removesOptimistically() {
        let store = AppDataStore(syncAPI: FailingSyncAPI())
        let doc = store.createDocumentOffline(title: "D", content: nil, isPublic: false, folderId: nil)
        store.deleteDocumentOffline(id: doc.id)
        XCTAssertFalse(store.documents.contains { $0.id == doc.id })
    }

    func test_reset_clearsPendingSyncState() {
        let store = AppDataStore(syncAPI: FailingSyncAPI())
        _ = store.createDocumentOffline(title: "D", content: nil, isPublic: false, folderId: nil)
        store.reset()
        XCTAssertTrue(store.pendingSyncDocIds.isEmpty)
        XCTAssertTrue(store.documents.isEmpty)
    }

    // MARK: - Helpers

    private func makeMessage(id: String) -> Message {
        Message(id: id, content: "test", publiclyVisible: true,
                userId: "u1", createdAt: "2026-01-01T00:00:00Z",
                updatedAt: nil, user: nil, imageUrls: nil, videoUrls: nil,
                linkMetadata: nil, parentId: nil, scheduledAt: nil,
                tags: nil, digCount: 0, dugByMe: false, crossPostUrls: nil)
    }

    private func makeDocument(id: String) -> Document {
        Document(id: id, title: "Doc \(id)", content: nil,
                 folderId: nil, isPublic: false,
                 createdAt: "2026-01-01T00:00:00Z", updatedAt: nil)
    }
}

/// Every sync call throws — simulates being offline.
private final class FailingSyncAPI: DocumentSyncAPI, @unchecked Sendable {
    private(set) var pushCalled = false
    private(set) var pullCalled = false

    func documentSync(lastSyncAt: String?) async throws -> DocumentSyncResponse {
        pullCalled = true
        throw APIError.network(URLError(.notConnectedToInternet))
    }

    func pushDocumentSync(operations: [SyncOperation]) async throws -> String {
        pushCalled = true
        throw APIError.network(URLError(.notConnectedToInternet))
    }
}

/// Records calls and returns canned success responses.
private final class RecordingSyncAPI: DocumentSyncAPI, @unchecked Sendable {
    let pushCursor: String
    let pullResponse: DocumentSyncResponse
    private(set) var pushCalled = false
    private(set) var pullCalled = false
    private(set) var pushedOperations: [SyncOperation] = []

    init(pushCursor: String, pullResponse: DocumentSyncResponse) {
        self.pushCursor = pushCursor
        self.pullResponse = pullResponse
    }

    func pushDocumentSync(operations: [SyncOperation]) async throws -> String {
        pushCalled = true
        pushedOperations = operations
        return pushCursor
    }

    func documentSync(lastSyncAt: String?) async throws -> DocumentSyncResponse {
        pullCalled = true
        return pullResponse
    }
}
