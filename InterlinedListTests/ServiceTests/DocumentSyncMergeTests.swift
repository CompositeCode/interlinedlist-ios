import XCTest
@testable import InterlinedList

final class DocumentSyncMergeTests: XCTestCase {
    private func doc(_ id: String, title: String = "t", folderId: String? = nil,
                     updatedAt: String? = nil, deletedAt: String? = nil) -> Document {
        Document(id: id, title: title, folderId: folderId, updatedAt: updatedAt, deletedAt: deletedAt)
    }

    private func folder(_ id: String, name: String = "n", parentId: String? = nil,
                        updatedAt: String? = nil, deletedAt: String? = nil) -> DocumentFolder {
        DocumentFolder(id: id, name: name, parentId: parentId, updatedAt: updatedAt, deletedAt: deletedAt)
    }

    func test_apply_emptyDelta_isNoOpExceptCursor() {
        let state = DocumentSyncState(folders: [folder("f1")], documents: [doc("d1")], lastSyncAt: "cursor0")
        let delta = DocumentSyncResponse(folders: [], documents: [], lastSyncAt: "cursor1")
        let merged = DocumentSyncMerge.apply(delta: delta, to: state)
        XCTAssertEqual(merged.folders.map(\.id), ["f1"])
        XCTAssertEqual(merged.documents.map(\.id), ["d1"])
        XCTAssertEqual(merged.lastSyncAt, "cursor1")
    }

    func test_apply_nilDeltaCursor_keepsExistingCursor() {
        let state = DocumentSyncState(folders: [], documents: [], lastSyncAt: "cursor0")
        let delta = DocumentSyncResponse(folders: [], documents: [], lastSyncAt: nil)
        let merged = DocumentSyncMerge.apply(delta: delta, to: state)
        XCTAssertEqual(merged.lastSyncAt, "cursor0")
    }

    func test_apply_insertsNewDocument() {
        let state = DocumentSyncState(folders: [], documents: [doc("d1")], lastSyncAt: nil)
        let delta = DocumentSyncResponse(documents: [doc("d2")], lastSyncAt: "c1")
        let merged = DocumentSyncMerge.apply(delta: delta, to: state)
        XCTAssertEqual(Set(merged.documents.map(\.id)), ["d1", "d2"])
    }

    func test_apply_upsertsChangedDocumentInPlace() {
        let state = DocumentSyncState(folders: [], documents: [doc("d1", title: "old"), doc("d2")], lastSyncAt: nil)
        let delta = DocumentSyncResponse(documents: [doc("d1", title: "new", updatedAt: "2026-07-31T00:00:00Z")], lastSyncAt: "c1")
        let merged = DocumentSyncMerge.apply(delta: delta, to: state)
        XCTAssertEqual(merged.documents.count, 2)
        let d1 = merged.documents.first { $0.id == "d1" }
        XCTAssertEqual(d1?.title, "new")
        XCTAssertEqual(d1?.updatedAt, "2026-07-31T00:00:00Z")
        // Order is preserved: d1 stays at its original index.
        XCTAssertEqual(merged.documents.first?.id, "d1")
    }

    func test_apply_removesTombstonedDocumentById() {
        let state = DocumentSyncState(folders: [], documents: [doc("d1"), doc("d2")], lastSyncAt: nil)
        let delta = DocumentSyncResponse(documents: [doc("d1", deletedAt: "2026-07-31T00:00:00Z")], lastSyncAt: "c1")
        let merged = DocumentSyncMerge.apply(delta: delta, to: state)
        XCTAssertEqual(merged.documents.map(\.id), ["d2"])
    }

    func test_apply_tombstoneForUnknownDocument_isNoOp() {
        let state = DocumentSyncState(folders: [], documents: [doc("d1")], lastSyncAt: nil)
        let delta = DocumentSyncResponse(documents: [doc("d99", deletedAt: "2026-07-31T00:00:00Z")], lastSyncAt: "c1")
        let merged = DocumentSyncMerge.apply(delta: delta, to: state)
        XCTAssertEqual(merged.documents.map(\.id), ["d1"])
    }

    func test_apply_insertsUpdatesAndDeletesFolders() {
        let state = DocumentSyncState(folders: [folder("f1"), folder("f2", name: "old")], documents: [], lastSyncAt: nil)
        let delta = DocumentSyncResponse(
            folders: [
                folder("f2", name: "renamed"),
                folder("f3"),
                folder("f1", deletedAt: "2026-07-31T00:00:00Z"),
            ],
            lastSyncAt: "c1"
        )
        let merged = DocumentSyncMerge.apply(delta: delta, to: state)
        XCTAssertEqual(Set(merged.folders.map(\.id)), ["f2", "f3"])
        XCTAssertEqual(merged.folders.first { $0.id == "f2" }?.name, "renamed")
    }

    func test_apply_cursorAdvancesToDeltaValue() {
        let state = DocumentSyncState(folders: [], documents: [], lastSyncAt: "2026-07-30T00:00:00Z")
        let delta = DocumentSyncResponse(documents: [doc("d1")], lastSyncAt: "2026-07-31T00:00:00Z")
        let merged = DocumentSyncMerge.apply(delta: delta, to: state)
        XCTAssertEqual(merged.lastSyncAt, "2026-07-31T00:00:00Z")
    }

    // MARK: - Slice 3: protectingIds

    func test_apply_protectedDocument_keepsLocalVersion() {
        let state = DocumentSyncState(folders: [], documents: [doc("d1", title: "local edit")], lastSyncAt: nil)
        let delta = DocumentSyncResponse(
            documents: [doc("d1", title: "server version", updatedAt: "2026-08-02T00:00:00Z")],
            lastSyncAt: "c1")
        let merged = DocumentSyncMerge.apply(delta: delta, to: state, protectingIds: ["d1"])
        XCTAssertEqual(merged.documents.first { $0.id == "d1" }?.title, "local edit")
    }

    func test_apply_protectedDocumentTombstone_keepsLocalVersion() {
        let state = DocumentSyncState(folders: [], documents: [doc("d1", title: "local")], lastSyncAt: nil)
        let delta = DocumentSyncResponse(
            documents: [doc("d1", deletedAt: "2026-08-02T00:00:00Z")], lastSyncAt: "c1")
        let merged = DocumentSyncMerge.apply(delta: delta, to: state, protectingIds: ["d1"])
        XCTAssertTrue(merged.documents.contains { $0.id == "d1" }, "protected doc is not tombstoned")
    }

    func test_apply_nonProtectedDocuments_stillMergeWhenSomeProtected() {
        let state = DocumentSyncState(folders: [], documents: [doc("d1", title: "local")], lastSyncAt: nil)
        let delta = DocumentSyncResponse(documents: [
            doc("d1", title: "server", updatedAt: "2026-08-02T00:00:00Z"),
            doc("d2", title: "other", updatedAt: "2026-08-02T00:00:00Z"),
        ], lastSyncAt: "c1")
        let merged = DocumentSyncMerge.apply(delta: delta, to: state, protectingIds: ["d1"])
        XCTAssertEqual(merged.documents.first { $0.id == "d1" }?.title, "local")
        XCTAssertEqual(merged.documents.first { $0.id == "d2" }?.title, "other")
    }

    func test_apply_foldersAreNeverProtected() {
        let state = DocumentSyncState(folders: [folder("f1", name: "old")], documents: [], lastSyncAt: nil)
        let delta = DocumentSyncResponse(folders: [folder("f1", name: "new")], lastSyncAt: "c1")
        let merged = DocumentSyncMerge.apply(delta: delta, to: state, protectingIds: ["f1"])
        XCTAssertEqual(merged.folders.first { $0.id == "f1" }?.name, "new")
    }

    func test_apply_preservesOutboxLocalStatesAndBaselines() {
        var state = DocumentSyncState(documents: [doc("d1")], lastSyncAt: "c0")
        state.outbox = [SyncOperation(op: .update, type: .document, data: SyncOpData(id: "d1", title: "x"))]
        state.localStates = ["d1": .dirty]
        state.baselines = ["d1": "2026-08-01T00:00:00Z"]
        let delta = DocumentSyncResponse(documents: [doc("d2")], lastSyncAt: "c1")
        let merged = DocumentSyncMerge.apply(delta: delta, to: state)
        XCTAssertEqual(merged.outbox.count, 1)
        XCTAssertEqual(merged.localStates["d1"], .dirty)
        XCTAssertEqual(merged.baselines["d1"], "2026-08-01T00:00:00Z")
    }

    func test_apply_deletedRowNeverAppearsInMergedState() {
        // Full-state pull (no cursor) may include a tombstone for a row we never had.
        let state = DocumentSyncState()
        let delta = DocumentSyncResponse(
            folders: [folder("f1")],
            documents: [doc("d1"), doc("d2", deletedAt: "2026-07-31T00:00:00Z")],
            lastSyncAt: "c1"
        )
        let merged = DocumentSyncMerge.apply(delta: delta, to: state)
        XCTAssertEqual(merged.documents.map(\.id), ["d1"])
        XCTAssertFalse(merged.documents.contains { $0.deletedAt != nil })
    }
}
