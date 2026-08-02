import XCTest
@testable import InterlinedList

final class DocumentSyncOutboxTests: XCTestCase {

    private func createOp(_ id: String, title: String = "t", content: String? = nil,
                          folderId: String? = nil, isPublic: Bool? = nil) -> SyncOperation {
        SyncOperation(op: .create, type: .document,
                      data: SyncOpData(id: id, folderId: folderId, title: title,
                                       content: content, isPublic: isPublic))
    }

    private func updateOp(_ id: String, title: String? = nil, content: String? = nil,
                          folderId: String? = nil, isPublic: Bool? = nil) -> SyncOperation {
        SyncOperation(op: .update, type: .document,
                      data: SyncOpData(id: id, folderId: folderId, title: title,
                                       content: content, isPublic: isPublic))
    }

    private func deleteOp(_ id: String) -> SyncOperation {
        SyncOperation(op: .delete, type: .document, data: SyncOpData(id: id))
    }

    // MARK: - Enqueue basics

    func test_enqueue_create_appendsOpAndMarksDirty() {
        var state = DocumentSyncState()
        DocumentSyncOutbox.enqueue(createOp("d1", title: "Hello"), into: &state)
        XCTAssertEqual(state.outbox.count, 1)
        XCTAssertEqual(state.outbox.first?.op, .create)
        XCTAssertEqual(state.localStates["d1"], .dirty)
    }

    func test_enqueue_distinctIds_keepsBothOps() {
        var state = DocumentSyncState()
        DocumentSyncOutbox.enqueue(createOp("d1"), into: &state)
        DocumentSyncOutbox.enqueue(createOp("d2"), into: &state)
        XCTAssertEqual(state.outbox.count, 2)
        XCTAssertEqual(Set(state.outbox.map { $0.data.id }), ["d1", "d2"])
    }

    // MARK: - Coalescing: create then updates → single create

    func test_enqueue_createThenUpdate_collapsesToSingleCreateWithLatestFields() {
        var state = DocumentSyncState()
        DocumentSyncOutbox.enqueue(createOp("d1", title: "Draft", content: "a"), into: &state)
        DocumentSyncOutbox.enqueue(updateOp("d1", title: "Final", content: "b"), into: &state)
        XCTAssertEqual(state.outbox.count, 1)
        let op = state.outbox.first
        XCTAssertEqual(op?.op, .create, "a create absorbs the update — the row was never on the server")
        XCTAssertEqual(op?.data.title, "Final")
        XCTAssertEqual(op?.data.content, "b")
        XCTAssertEqual(state.localStates["d1"], .dirty)
    }

    func test_enqueue_createThenPartialUpdate_mergesUntouchedFields() {
        var state = DocumentSyncState()
        DocumentSyncOutbox.enqueue(createOp("d1", title: "Title", content: "Body", isPublic: false), into: &state)
        // Only isPublic changes; title/content must survive the merge.
        DocumentSyncOutbox.enqueue(updateOp("d1", isPublic: true), into: &state)
        XCTAssertEqual(state.outbox.count, 1)
        let op = state.outbox.first
        XCTAssertEqual(op?.op, .create)
        XCTAssertEqual(op?.data.title, "Title")
        XCTAssertEqual(op?.data.content, "Body")
        XCTAssertEqual(op?.data.isPublic, true)
    }

    // MARK: - Coalescing: update then update → single update

    func test_enqueue_updateThenUpdate_collapsesToSingleUpdate() {
        var state = DocumentSyncState()
        DocumentSyncOutbox.enqueue(updateOp("d1", title: "One"), into: &state)
        DocumentSyncOutbox.enqueue(updateOp("d1", title: "Two"), into: &state)
        XCTAssertEqual(state.outbox.count, 1)
        XCTAssertEqual(state.outbox.first?.op, .update)
        XCTAssertEqual(state.outbox.first?.data.title, "Two")
    }

    func test_enqueue_updateThenUpdate_mergesDistinctFields() {
        var state = DocumentSyncState()
        DocumentSyncOutbox.enqueue(updateOp("d1", title: "One"), into: &state)
        DocumentSyncOutbox.enqueue(updateOp("d1", content: "Body"), into: &state)
        XCTAssertEqual(state.outbox.count, 1)
        let op = state.outbox.first
        XCTAssertEqual(op?.data.title, "One")
        XCTAssertEqual(op?.data.content, "Body")
    }

    // MARK: - Coalescing: delete of a not-yet-synced create cancels both

    func test_enqueue_deleteOfUnsyncedCreate_cancelsBoth() {
        var state = DocumentSyncState()
        DocumentSyncOutbox.enqueue(createOp("d1"), into: &state)
        DocumentSyncOutbox.enqueue(deleteOp("d1"), into: &state)
        XCTAssertTrue(state.outbox.isEmpty, "a create+delete of the same never-synced row is a no-op")
        XCTAssertNil(state.localStates["d1"])
    }

    func test_enqueue_deleteOfCreateThenUpdate_cancelsBoth() {
        var state = DocumentSyncState()
        DocumentSyncOutbox.enqueue(createOp("d1"), into: &state)
        DocumentSyncOutbox.enqueue(updateOp("d1", title: "edited"), into: &state)
        DocumentSyncOutbox.enqueue(deleteOp("d1"), into: &state)
        XCTAssertTrue(state.outbox.isEmpty)
        XCTAssertNil(state.localStates["d1"])
    }

    // MARK: - Coalescing: delete of a synced/updated row → single delete

    func test_enqueue_deleteOfUpdate_collapsesToSingleDelete() {
        var state = DocumentSyncState()
        DocumentSyncOutbox.enqueue(updateOp("d1", title: "edited"), into: &state)
        DocumentSyncOutbox.enqueue(deleteOp("d1"), into: &state)
        XCTAssertEqual(state.outbox.count, 1)
        XCTAssertEqual(state.outbox.first?.op, .delete)
        XCTAssertEqual(state.outbox.first?.data.id, "d1")
        XCTAssertEqual(state.localStates["d1"], .deleted)
    }

    func test_enqueue_deleteOfSyncedRow_appendsDelete() {
        var state = DocumentSyncState()
        DocumentSyncOutbox.enqueue(deleteOp("d1"), into: &state)
        XCTAssertEqual(state.outbox.count, 1)
        XCTAssertEqual(state.outbox.first?.op, .delete)
        XCTAssertEqual(state.localStates["d1"], .deleted)
    }

    // MARK: - Push payload

    func test_pushPayload_returnsCurrentOutbox() {
        var state = DocumentSyncState()
        DocumentSyncOutbox.enqueue(createOp("d1"), into: &state)
        DocumentSyncOutbox.enqueue(createOp("d2"), into: &state)
        let payload = DocumentSyncOutbox.pushPayload(from: state)
        XCTAssertEqual(payload.map { $0.data.id }, ["d1", "d2"])
    }

    // MARK: - Clear after push

    func test_clearOutbox_removesPushedOpsAndSettlesStates() {
        var state = DocumentSyncState()
        DocumentSyncOutbox.enqueue(createOp("d1"), into: &state)
        DocumentSyncOutbox.enqueue(deleteOp("d2"), into: &state)
        let pushed = DocumentSyncOutbox.pushPayload(from: state)
        DocumentSyncOutbox.clearOutbox(pushed, from: &state)
        XCTAssertTrue(state.outbox.isEmpty)
        XCTAssertEqual(state.localStates["d1"], .synced, "pushed create becomes synced")
        XCTAssertNil(state.localStates["d2"], "pushed delete is forgotten")
    }

    func test_clearOutbox_keepsOpsQueuedAfterTheSnapshot() {
        var state = DocumentSyncState()
        DocumentSyncOutbox.enqueue(createOp("d1"), into: &state)
        let pushed = DocumentSyncOutbox.pushPayload(from: state)
        // A new edit to a different id arrives while the push is in flight.
        DocumentSyncOutbox.enqueue(createOp("d2"), into: &state)
        DocumentSyncOutbox.clearOutbox(pushed, from: &state)
        XCTAssertEqual(state.outbox.map { $0.data.id }, ["d2"], "only the pushed op is cleared")
        XCTAssertEqual(state.localStates["d1"], .synced)
        XCTAssertEqual(state.localStates["d2"], .dirty)
    }

    // MARK: - dirtyIds

    func test_dirtyIds_reflectsPendingCreatesAndUpdatesOnly() {
        var state = DocumentSyncState()
        DocumentSyncOutbox.enqueue(createOp("d1"), into: &state)
        DocumentSyncOutbox.enqueue(updateOp("d2", title: "x"), into: &state)
        DocumentSyncOutbox.enqueue(deleteOp("d3"), into: &state)
        XCTAssertEqual(state.dirtyIds, ["d1", "d2"])
    }
}
