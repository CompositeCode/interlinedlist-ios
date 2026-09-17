import Combine
import XCTest
@testable import InterlinedList

@MainActor
final class AppDataStoreTests: XCTestCase {
    var sut: AppDataStore!

    /// Ids handed out by `makeCachedUserId()`, cleared from the on-disk cache in
    /// `tearDown` so a run leaves no feed JSON behind in the simulator.
    private var seededUserIds: [String] = []

    override func setUp() {
        super.setUp()
        sut = AppDataStore()
    }

    override func tearDown() async throws {
        let uids = seededUserIds
        seededUserIds = []
        let cache = DataCache()
        for uid in uids { await cache.clearAll(prefix: uid) }
        try await super.tearDown()
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

    // MARK: - updateFeedMessage

    func test_updateFeedMessage_replacesTheRowContent() {
        sut.insertFeedMessage(makeMessage(id: "a", content: "before"))
        sut.updateFeedMessage(makeMessage(id: "a", content: "after"))
        XCTAssertEqual(sut.feedMessages.first?.content, "after")
    }

    func test_updateFeedMessage_keepsCountAndOrder() {
        sut.insertFeedMessage(makeMessage(id: "a"))
        sut.insertFeedMessage(makeMessage(id: "b"))
        sut.updateFeedMessage(makeMessage(id: "a", content: "edited"))
        XCTAssertEqual(sut.feedMessages.map(\.id), ["b", "a"])
        XCTAssertEqual(sut.feedMessages.last?.content, "edited")
    }

    func test_updateFeedMessage_leavesOtherRowsAlone() {
        sut.insertFeedMessage(makeMessage(id: "a", content: "a-content"))
        sut.insertFeedMessage(makeMessage(id: "b", content: "b-content"))
        sut.updateFeedMessage(makeMessage(id: "b", content: "edited"))
        XCTAssertEqual(sut.feedMessages.last?.content, "a-content")
    }

    func test_updateFeedMessage_unknownId_isANoOp() {
        sut.insertFeedMessage(makeMessage(id: "a", content: "kept"))
        sut.updateFeedMessage(makeMessage(id: "ghost", content: "ignored"))
        XCTAssertEqual(sut.feedMessages.map(\.id), ["a"])
        XCTAssertEqual(sut.feedMessages.first?.content, "kept")
    }

    // MARK: - removeFeedMessage

    func test_removeFeedMessage_dropsTheRow() {
        sut.insertFeedMessage(makeMessage(id: "a"))
        sut.removeFeedMessage(id: "a")
        XCTAssertTrue(sut.feedMessages.isEmpty)
    }

    func test_removeFeedMessage_keepsTheOtherRowsInOrder() {
        sut.insertFeedMessage(makeMessage(id: "a"))
        sut.insertFeedMessage(makeMessage(id: "b"))
        sut.insertFeedMessage(makeMessage(id: "c"))
        sut.removeFeedMessage(id: "b")
        XCTAssertEqual(sut.feedMessages.map(\.id), ["c", "a"])
    }

    func test_removeFeedMessage_unknownId_isANoOp() {
        sut.insertFeedMessage(makeMessage(id: "a"))
        sut.removeFeedMessage(id: "ghost")
        XCTAssertEqual(sut.feedMessages.map(\.id), ["a"])
    }

    func test_removeFeedMessage_unknownId_doesNotMoveTheRevision() {
        sut.insertFeedMessage(makeMessage(id: "a"))
        let before = sut.feedRevision
        sut.removeFeedMessage(id: "ghost")
        XCTAssertEqual(sut.feedRevision, before)
    }

    func test_removeFeedMessage_movesTheRevision() {
        sut.insertFeedMessage(makeMessage(id: "a"))
        let before = sut.feedRevision
        sut.removeFeedMessage(id: "a")
        XCTAssertGreaterThan(sut.feedRevision, before)
    }

    /// `insertFeedMessage` deliberately does not deduplicate (see
    /// `test_insertFeedMessage_doesNotDuplicateExistingMessage`), so removing a single
    /// index would leave a copy of the deleted post behind.
    func test_removeFeedMessage_removesEveryCopyOfADuplicatedId() {
        sut.insertFeedMessage(makeMessage(id: "dup"))
        sut.insertFeedMessage(makeMessage(id: "dup"))
        sut.removeFeedMessage(id: "dup")
        XCTAssertTrue(sut.feedMessages.isEmpty)
    }

    // MARK: - removeFeedMessage: the persisted cache

    func test_removeFeedMessage_dropsTheRowFromThePersistedCache() async {
        let uid = makeCachedUserId()
        sut.onUserIdAvailable(uid)
        sut.insertFeedMessage(makeMessage(id: "a"))
        sut.insertFeedMessage(makeMessage(id: "b"))
        let seeded = await cachedFeedIds(forUserId: uid, awaiting: ["b", "a"])
        XCTAssertEqual(seeded, ["b", "a"], "cache was not seeded; the assertion below would be vacuous")

        sut.removeFeedMessage(id: "a")

        let after = await cachedFeedIds(forUserId: uid, awaiting: ["b"])
        XCTAssertEqual(after, ["b"])
    }

    /// The reported bug, end to end: a deleted post must not come back on the next
    /// launch that reads the cache. The relaunched store hydrates from disk only —
    /// `onUserIdAvailable` touches no network.
    func test_removedMessage_staysDeletedAcrossARelaunch() async {
        let uid = makeCachedUserId()
        sut.onUserIdAvailable(uid)
        sut.insertFeedMessage(makeMessage(id: "keep"))
        sut.insertFeedMessage(makeMessage(id: "gone"))
        let seeded = await cachedFeedIds(forUserId: uid, awaiting: ["gone", "keep"])
        XCTAssertEqual(seeded, ["gone", "keep"], "cache was not seeded")

        sut.removeFeedMessage(id: "gone")
        _ = await cachedFeedIds(forUserId: uid, awaiting: ["keep"])

        let relaunched = AppDataStore()
        relaunched.onUserIdAvailable(uid)
        let ids = await feedIds(of: relaunched, awaiting: ["keep"])
        XCTAssertEqual(ids, ["keep"])
    }

    // MARK: - removeFeedMessage: replies

    /// Deliberate: no cascade. The feed page cannot hold a reply — `GET /api/messages`
    /// filters `parentId: null`, and `ComposeView` skips `insertFeedMessage` when it is
    /// replying — so a parent's replies are never in this cache to remove. The backend
    /// cascades (`onDelete: Cascade`), which settles the server side. This pins the
    /// decision: only the named id goes.
    func test_removeFeedMessage_removesOnlyTheNamedId_leavingAReplyRow() {
        sut.insertFeedMessage(makeMessage(id: "parent"))
        sut.insertFeedMessage(makeMessage(id: "reply", parentId: "parent"))
        sut.removeFeedMessage(id: "parent")
        XCTAssertEqual(sut.feedMessages.map(\.id), ["reply"])
    }

    /// An orphaned reply is an ordinary row: no view branches on `parentId`, so a
    /// dangling parent id renders as a standalone post rather than breaking.
    func test_removeFeedMessage_orphanedReply_keepsItsFieldsIntact() {
        sut.insertFeedMessage(makeMessage(id: "parent"))
        sut.insertFeedMessage(makeMessage(id: "reply", content: "a reply", parentId: "parent"))
        sut.removeFeedMessage(id: "parent")
        let orphan = sut.feedMessages.first
        XCTAssertEqual(orphan?.id, "reply")
        XCTAssertEqual(orphan?.content, "a reply")
        XCTAssertEqual(orphan?.parentId, "parent")
    }

    /// The orphan has to survive the cache round-trip too: `[Message]` decodes all or
    /// nothing, so a row that failed to decode would take the whole feed cache with it.
    func test_removeFeedMessage_orphanedReply_survivesTheCacheRoundTrip() async {
        let uid = makeCachedUserId()
        sut.onUserIdAvailable(uid)
        sut.insertFeedMessage(makeMessage(id: "parent"))
        sut.insertFeedMessage(makeMessage(id: "reply", parentId: "parent"))
        let seeded = await cachedFeedIds(forUserId: uid, awaiting: ["reply", "parent"])
        XCTAssertEqual(seeded, ["reply", "parent"], "cache was not seeded")

        sut.removeFeedMessage(id: "parent")
        _ = await cachedFeedIds(forUserId: uid, awaiting: ["reply"])

        let relaunched = AppDataStore()
        relaunched.onUserIdAvailable(uid)
        let ids = await feedIds(of: relaunched, awaiting: ["reply"])
        XCTAssertEqual(ids, ["reply"])
        XCTAssertEqual(relaunched.feedMessages.first?.parentId, "parent")
    }

    // MARK: - removeFeedMessage: the view's working copy

    /// The optimistic half. `FeedView.deleteMessage` drops the row from its own copy
    /// and then tells the store; a merge of the two afterwards must leave it gone.
    func test_storeRowRemoval_withTheLocalRemoval_leavesTheRowGone() {
        sut.insertFeedMessage(makeMessage(id: "a"))
        sut.insertFeedMessage(makeMessage(id: "b"))
        var viewCopy = sut.feedMessages

        sut.removeFeedMessage(id: "a")
        viewCopy.removeAll { $0.id == "a" }

        let merged = FeedMerge.merge(existing: viewCopy, incoming: sut.feedMessages)
        XCTAssertEqual(merged.messages.map(\.id), ["b"])
    }

    /// Why that local removal is load-bearing rather than merely faster: `FeedMerge`
    /// keeps rows the store does not hold, which is how paginated pages survive a
    /// merge. The store call alone cannot evict a row the view already holds.
    func test_storeRowRemoval_withoutTheLocalRemoval_keepsTheRowOnScreen() {
        sut.insertFeedMessage(makeMessage(id: "a"))
        let viewCopy = sut.feedMessages

        sut.removeFeedMessage(id: "a")

        let merged = FeedMerge.merge(existing: viewCopy, incoming: sut.feedMessages)
        XCTAssertEqual(merged.messages.map(\.id), ["a"])
    }

    // MARK: - feedRevision

    /// The whole point of the revision: `Message` compares by id, so neither the
    /// array nor its count moves when a row is edited in place.
    func test_feedRevision_movesWhenARowIsEditedInPlace() {
        sut.insertFeedMessage(makeMessage(id: "a", content: "before"))
        let before = sut.feedRevision
        let countBefore = sut.feedMessages.count
        sut.updateFeedMessage(makeMessage(id: "a", content: "after"))
        XCTAssertEqual(sut.feedMessages.count, countBefore)
        XCTAssertGreaterThan(sut.feedRevision, before)
    }

    func test_feedRevision_movesWhenARowIsInserted() {
        let before = sut.feedRevision
        sut.insertFeedMessage(makeMessage(id: "a"))
        XCTAssertGreaterThan(sut.feedRevision, before)
    }

    func test_feedRevision_doesNotMoveForAnUnknownId() {
        sut.insertFeedMessage(makeMessage(id: "a"))
        let before = sut.feedRevision
        sut.updateFeedMessage(makeMessage(id: "ghost"))
        XCTAssertEqual(sut.feedRevision, before)
    }

    // MARK: - store mutation reaching the feed's working copy

    /// End of the chain the bug broke: the store edits a row, and the copy `FeedView`
    /// renders from picks the edit up through `FeedMerge` without a reload.
    func test_storeRowEdit_reachesTheViewsWorkingCopy() {
        sut.insertFeedMessage(makeMessage(id: "a", content: "before"))
        let viewCopy = sut.feedMessages
        let revisionBefore = sut.feedRevision

        sut.updateFeedMessage(makeMessage(id: "a", content: "after"))

        XCTAssertGreaterThan(sut.feedRevision, revisionBefore)
        let merged = FeedMerge.merge(existing: viewCopy, incoming: sut.feedMessages)
        XCTAssertEqual(merged.messages.count, 1)
        XCTAssertEqual(merged.messages.first?.content, "after")
    }

    /// The view's copy runs ahead of the store once pagination has appended a page;
    /// a store edit must not drop those rows.
    func test_storeRowEdit_keepsPaginatedRowsTheStoreNeverSaw() {
        sut.insertFeedMessage(makeMessage(id: "p1", content: "before"))
        let viewCopy = sut.feedMessages + [makeMessage(id: "p2"), makeMessage(id: "p3")]

        sut.updateFeedMessage(makeMessage(id: "p1", content: "after"))

        let merged = FeedMerge.merge(existing: viewCopy, incoming: sut.feedMessages)
        XCTAssertEqual(merged.messages.map(\.id), ["p1", "p2", "p3"])
        XCTAssertEqual(merged.messages.first?.content, "after")
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

    /// G17. Shared-in lists are another account's data, so signing out must drop
    /// them along with the owned lists.
    func test_reset_clearsWatchedLists() {
        sut.reset()
        XCTAssertTrue(sut.watchedLists.isEmpty)
        XCTAssertTrue(sut.userLists.isEmpty)
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

    func test_createDocumentOffline_pushedOpCarriesRelativePath() async {
        // The sync POST silently drops a create/update op without a non-empty
        // relativePath, so the queued op (and the optimistic doc) must carry one.
        let api = RecordingSyncAPI(pushCursor: "c1",
                                   pullResponse: DocumentSyncResponse(lastSyncAt: "c1"))
        let store = AppDataStore(syncAPI: api)
        let doc = store.createDocumentOffline(title: "Draft", content: "hi", isPublic: false, folderId: nil)
        await store.pushOutbox()
        let op = api.pushedOperations.first { $0.data.id == doc.id }
        XCTAssertEqual(op?.op, .create)
        XCTAssertEqual(op?.data.relativePath?.isEmpty, false)
        XCTAssertEqual(store.documents.first { $0.id == doc.id }?.relativePath?.isEmpty, false)
    }

    func test_updateDocumentOffline_pushedOpEchoesExistingRelativePath() async {
        // Seed a pulled doc with a known server path, then edit it: the update op
        // must echo that path so the server accepts the edit.
        let api = ControllableSyncAPI()
        api.nextPull = DocumentSyncResponse(
            documents: [Document(id: "d1", title: "Server", content: "v1", folderId: nil,
                                 isPublic: false, createdAt: "2026-07-01T00:00:00Z",
                                 updatedAt: "2026-07-01T00:00:00Z", relativePath: "server-path.md")],
            lastSyncAt: "c1")
        let store = AppDataStore(syncAPI: api)
        await store.pushOutbox()

        api.nextPull = nil
        _ = store.updateDocumentOffline(id: "d1", title: "Edited", content: "v2",
                                        isPublic: false, folderId: nil)
        api.nextPull = DocumentSyncResponse(lastSyncAt: "c2")
        await store.pushOutbox()

        let op = api.lastPushedOps.first { $0.data.id == "d1" }
        XCTAssertEqual(op?.op, .update)
        XCTAssertEqual(op?.data.relativePath, "server-path.md")
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

    // MARK: - Slice 3: pull-first conflict-copy cycle

    func test_syncCycle_dirtyDocWithNewerServer_keepsLocalAndCreatesConflictCopy() async {
        let api = ControllableSyncAPI()

        // Cycle 1: a clean pull seeds document d1 and records its baseline (T1).
        api.nextPull = DocumentSyncResponse(
            documents: [makeSyncedDoc(id: "d1", title: "server v1", updatedAt: "2026-08-01T00:00:00Z")],
            lastSyncAt: "cursor-1")
        let store = AppDataStore(syncAPI: api)
        await store.pushOutbox()
        XCTAssertTrue(store.documents.contains { $0.id == "d1" })
        XCTAssertTrue(store.syncConflicts.isEmpty, "clean pull is not a conflict")

        // A pull that throws keeps the debounced push (from the edit below) a no-op
        // while we stage the divergent server state deterministically.
        api.nextPull = nil
        _ = store.updateDocumentOffline(id: "d1", title: "my local edit",
                                        content: "local body", isPublic: false, folderId: nil)
        XCTAssertTrue(store.pendingSyncDocIds.contains("d1"))

        // Cycle 2: the server has a NEWER version of d1 → conflict-copy.
        api.nextPull = DocumentSyncResponse(
            documents: [makeSyncedDoc(id: "d1", title: "server v2", content: "server body",
                                      updatedAt: "2026-08-02T00:00:00Z")],
            lastSyncAt: "cursor-2")
        api.nextPushCursor = "2026-08-02T12:00:00Z"
        await store.pushOutbox()

        // Local doc stays live (protected from the merge).
        let live = store.documents.first { $0.id == "d1" }
        XCTAssertEqual(live?.title, "my local edit")

        // A conflict copy of the SERVER version was created as a new doc.
        let copy = store.documents.first { $0.id != "d1" && $0.title.contains("conflicted copy") }
        XCTAssertNotNil(copy, "a conflict copy document exists")
        XCTAssertTrue(copy?.title.hasPrefix("server v2") == true)
        XCTAssertEqual(copy?.content, "server body")

        // Banner notice recorded for the conflicting doc.
        XCTAssertEqual(store.syncConflicts.count, 1)
        XCTAssertEqual(store.syncConflicts.first?.id, "d1")

        // Push drained both the local update and the new conflict-copy create.
        let pushedIds = Set(api.lastPushedOps.map { $0.data.id })
        XCTAssertTrue(pushedIds.contains("d1"), "local edit pushed")
        XCTAssertTrue(copy.map { pushedIds.contains($0.id) } ?? false, "conflict copy pushed")
        // Outbox cleared after the successful push.
        XCTAssertFalse(store.pendingSyncDocIds.contains("d1"))
    }

    func test_dismissSyncConflicts_clearsBanner() async {
        let api = ControllableSyncAPI()
        api.nextPull = DocumentSyncResponse(
            documents: [makeSyncedDoc(id: "d1", title: "v1", updatedAt: "2026-08-01T00:00:00Z")],
            lastSyncAt: "c1")
        let store = AppDataStore(syncAPI: api)
        await store.pushOutbox()
        api.nextPull = nil
        _ = store.updateDocumentOffline(id: "d1", title: "local", content: nil, isPublic: false, folderId: nil)
        api.nextPull = DocumentSyncResponse(
            documents: [makeSyncedDoc(id: "d1", title: "v2", updatedAt: "2026-08-02T00:00:00Z")],
            lastSyncAt: "c2")
        api.nextPushCursor = "2026-08-02T12:00:00Z"
        await store.pushOutbox()
        XCTAssertFalse(store.syncConflicts.isEmpty)
        store.dismissSyncConflicts()
        XCTAssertTrue(store.syncConflicts.isEmpty)
    }

    private func makeSyncedDoc(id: String, title: String, content: String? = nil,
                               updatedAt: String) -> Document {
        Document(id: id, title: title, content: content, folderId: nil, isPublic: false,
                 createdAt: "2026-07-01T00:00:00Z", updatedAt: updatedAt)
    }

    // MARK: - applyLinkMetadata

    private func link(_ url: String, title: String) -> LinkMetadataItem {
        LinkMetadataItem(url: url, platform: nil,
                         metadata: LinkMetadataItemContent(thumbnail: nil, title: title,
                                                           description: nil, text: nil, type: nil),
                         fetchStatus: nil)
    }

    func test_applyLinkMetadata_setsMetadataOnTargetMessage() {
        sut.insertFeedMessage(makeMessage(id: "m1"))

        sut.applyLinkMetadata([link("https://example.com", title: "Example")], toMessageId: "m1")

        let updated = sut.feedMessages.first { $0.id == "m1" }
        XCTAssertEqual(updated?.linkMetadata?.links.count, 1)
        XCTAssertEqual(updated?.linkMetadata?.links.first?.url, "https://example.com")
        XCTAssertEqual(updated?.linkMetadata?.links.first?.metadata?.title, "Example")
    }

    func test_applyLinkMetadata_leavesOtherMessagesUntouched() {
        sut.insertFeedMessage(makeMessage(id: "older"))
        sut.insertFeedMessage(makeMessage(id: "target"))
        sut.insertFeedMessage(makeMessage(id: "newer"))

        sut.applyLinkMetadata([link("https://example.com", title: "Example")], toMessageId: "target")

        XCTAssertNil(sut.feedMessages.first { $0.id == "older" }?.linkMetadata)
        XCTAssertNil(sut.feedMessages.first { $0.id == "newer" }?.linkMetadata)
        XCTAssertEqual(sut.feedMessages.map(\.id), ["newer", "target", "older"])
    }

    func test_applyLinkMetadata_replacesExistingMetadata() {
        let stale = LinkMetadata(links: [link("https://stale.example", title: "Stale")])
        sut.insertFeedMessage(makeMessage(id: "m1", linkMetadata: stale))

        sut.applyLinkMetadata([link("https://fresh.example", title: "Fresh")], toMessageId: "m1")

        let links = sut.feedMessages.first { $0.id == "m1" }?.linkMetadata?.links
        XCTAssertEqual(links?.count, 1)
        XCTAssertEqual(links?.first?.url, "https://fresh.example")
    }

    func test_applyLinkMetadata_unknownMessageId_isNoOp() {
        sut.insertFeedMessage(makeMessage(id: "m1"))

        sut.applyLinkMetadata([link("https://example.com", title: "Example")], toMessageId: "gone")

        XCTAssertEqual(sut.feedMessages.count, 1)
        XCTAssertNil(sut.feedMessages.first?.linkMetadata)
    }

    func test_applyLinkMetadata_emptyFeed_isNoOp() {
        sut.applyLinkMetadata([link("https://example.com", title: "Example")], toMessageId: "m1")
        XCTAssertTrue(sut.feedMessages.isEmpty)
    }

    /// `{ links: [] }` is what the route answers when it resolved nothing, so it
    /// must not blank a preview a feed fetch already supplied.
    func test_applyLinkMetadata_emptyLinks_leavesExistingMetadata() {
        let existing = LinkMetadata(links: [link("https://example.com", title: "Example")])
        sut.insertFeedMessage(makeMessage(id: "m1", linkMetadata: existing))

        sut.applyLinkMetadata([], toMessageId: "m1")

        XCTAssertEqual(sut.feedMessages.first?.linkMetadata?.links.first?.metadata?.title, "Example")
    }

    // MARK: - Helpers

    private func makeMessage(id: String, content: String = "test",
                             parentId: String? = nil,
                             linkMetadata: LinkMetadata? = nil) -> Message {
        Message(id: id, content: content, publiclyVisible: true,
                userId: "u1", createdAt: "2026-01-01T00:00:00Z",
                updatedAt: nil, user: nil, imageUrls: nil, videoUrls: nil,
                linkMetadata: linkMetadata, parentId: parentId, scheduledAt: nil,
                tags: nil, digCount: 0, dugByMe: false, crossPostUrls: nil)
    }

    /// A user id no other test (or earlier run) has cached under, so the feed-cache
    /// assertions read only what the test itself wrote.
    private func makeCachedUserId() -> String {
        let uid = "test-user-\(UUID().uuidString)"
        seededUserIds.append(uid)
        return uid
    }

    /// `saveFeedCache` writes through a detached `Task` into an actor, so the file is
    /// not on disk when the mutating call returns. Polls for the expected ids instead
    /// of sleeping a fixed interval, and returns whatever it last read so a failure
    /// reports the actual cached state.
    private func cachedFeedIds(forUserId uid: String,
                               awaiting expected: [String],
                               timeout: TimeInterval = 3.0) async -> [String]? {
        let cache = DataCache()
        let deadline = Date().addingTimeInterval(timeout)
        var last: [String]?
        repeat {
            let loaded: [Message]? = await cache.load(key: "\(uid)_feed")
            last = loaded?.map(\.id)
            if last == expected { return last }
            try? await Task.sleep(nanoseconds: 20_000_000)
        } while Date() < deadline
        return last
    }

    /// `onUserIdAvailable` hydrates from the cache in a detached `Task` — same polling
    /// reason as `cachedFeedIds`.
    private func feedIds(of store: AppDataStore,
                         awaiting expected: [String],
                         timeout: TimeInterval = 3.0) async -> [String] {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            let ids = store.feedMessages.map(\.id)
            if ids == expected { return ids }
            try? await Task.sleep(nanoseconds: 20_000_000)
        } while Date() < deadline
        return store.feedMessages.map(\.id)
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

/// A sequenceable mock: `nextPull` is served on the next pull (nil → throws, so a
/// stray debounced push is a harmless no-op); `nextPushCursor` is returned on the
/// next push, and the pushed ops are captured.
private final class ControllableSyncAPI: DocumentSyncAPI, @unchecked Sendable {
    var nextPull: DocumentSyncResponse?
    var nextPushCursor: String = "cursor-push"
    private(set) var lastPushedOps: [SyncOperation] = []

    func documentSync(lastSyncAt: String?) async throws -> DocumentSyncResponse {
        guard let pull = nextPull else {
            throw APIError.network(URLError(.notConnectedToInternet))
        }
        return pull
    }

    func pushDocumentSync(operations: [SyncOperation]) async throws -> String {
        lastPushedOps = operations
        return nextPushCursor
    }
}
