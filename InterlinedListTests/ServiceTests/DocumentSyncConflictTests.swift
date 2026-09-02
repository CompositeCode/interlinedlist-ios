import XCTest
@testable import InterlinedList

final class DocumentSyncConflictTests: XCTestCase {

    private func doc(_ id: String, title: String = "Notes", content: String? = nil,
                     folderId: String? = nil, isPublic: Bool? = nil,
                     updatedAt: String? = nil, deletedAt: String? = nil) -> Document {
        Document(id: id, title: title, content: content, folderId: folderId,
                 isPublic: isPublic, updatedAt: updatedAt, deletedAt: deletedAt)
    }

    /// 2026-08-02 12:00:00 UTC → stable local-date suffix for title assertions.
    private var fixedDate: Date {
        var c = DateComponents()
        c.year = 2026; c.month = 8; c.day = 2; c.hour = 12
        c.timeZone = TimeZone.current
        return Calendar(identifier: .gregorian).date(from: c) ?? Date(timeIntervalSince1970: 0)
    }

    // MARK: - detectConflicts

    func test_detectConflicts_dirtyAndServerNewer_isConflict() {
        let delta = DocumentSyncResponse(
            documents: [doc("d1", updatedAt: "2026-08-02T00:00:00Z")], lastSyncAt: "c1")
        let conflicts = DocumentSyncConflict.detectConflicts(
            delta: delta, dirtyIds: ["d1"], baselines: ["d1": "2026-08-01T00:00:00Z"])
        XCTAssertEqual(conflicts.map(\.id), ["d1"])
        XCTAssertEqual(conflicts.first?.serverDocument.updatedAt, "2026-08-02T00:00:00Z")
    }

    func test_detectConflicts_notDirty_isNoConflict() {
        let delta = DocumentSyncResponse(
            documents: [doc("d1", updatedAt: "2026-08-02T00:00:00Z")], lastSyncAt: "c1")
        let conflicts = DocumentSyncConflict.detectConflicts(
            delta: delta, dirtyIds: [], baselines: ["d1": "2026-08-01T00:00:00Z"])
        XCTAssertTrue(conflicts.isEmpty)
    }

    func test_detectConflicts_serverNotNewerThanBaseline_isNoConflict() {
        let delta = DocumentSyncResponse(
            documents: [doc("d1", updatedAt: "2026-08-01T00:00:00Z")], lastSyncAt: "c1")
        let conflicts = DocumentSyncConflict.detectConflicts(
            delta: delta, dirtyIds: ["d1"], baselines: ["d1": "2026-08-01T00:00:00Z"])
        XCTAssertTrue(conflicts.isEmpty, "equal updatedAt is not strictly newer")
    }

    func test_detectConflicts_dirtyWithNoBaseline_isNoConflict() {
        // A purely local create the server hasn't acknowledged has no shared
        // history to diverge from.
        let delta = DocumentSyncResponse(
            documents: [doc("d1", updatedAt: "2026-08-02T00:00:00Z")], lastSyncAt: "c1")
        let conflicts = DocumentSyncConflict.detectConflicts(
            delta: delta, dirtyIds: ["d1"], baselines: [:])
        XCTAssertTrue(conflicts.isEmpty)
    }

    func test_detectConflicts_serverTombstoneForDirty_isNoConflict() {
        // Deleted-elsewhere while locally dirty: the merge protects the local doc;
        // it is not treated here as a content conflict-copy.
        let delta = DocumentSyncResponse(
            documents: [doc("d1", updatedAt: "2026-08-02T00:00:00Z", deletedAt: "2026-08-02T00:00:00Z")],
            lastSyncAt: "c1")
        let conflicts = DocumentSyncConflict.detectConflicts(
            delta: delta, dirtyIds: ["d1"], baselines: ["d1": "2026-08-01T00:00:00Z"])
        XCTAssertTrue(conflicts.isEmpty)
    }

    func test_detectConflicts_serverMissingUpdatedAt_isNoConflict() {
        let delta = DocumentSyncResponse(documents: [doc("d1", updatedAt: nil)], lastSyncAt: "c1")
        let conflicts = DocumentSyncConflict.detectConflicts(
            delta: delta, dirtyIds: ["d1"], baselines: ["d1": "2026-08-01T00:00:00Z"])
        XCTAssertTrue(conflicts.isEmpty)
    }

    func test_detectConflicts_multipleRows_onlyDivergentDirtyOnesReturned() {
        let delta = DocumentSyncResponse(documents: [
            doc("dirtyNewer", updatedAt: "2026-08-02T00:00:00Z"),
            doc("dirtySame", updatedAt: "2026-08-01T00:00:00Z"),
            doc("cleanNewer", updatedAt: "2026-08-02T00:00:00Z"),
        ], lastSyncAt: "c1")
        let conflicts = DocumentSyncConflict.detectConflicts(
            delta: delta,
            dirtyIds: ["dirtyNewer", "dirtySame"],
            baselines: ["dirtyNewer": "2026-08-01T00:00:00Z",
                        "dirtySame": "2026-08-01T00:00:00Z",
                        "cleanNewer": "2026-08-01T00:00:00Z"])
        XCTAssertEqual(conflicts.map(\.id), ["dirtyNewer"])
    }

    // MARK: - makeConflictCopy

    func test_makeConflictCopy_hasNewIdDistinctFromOriginal() {
        let server = doc("d1", title: "Trip Plan", updatedAt: "2026-08-02T00:00:00Z")
        let copy = DocumentSyncConflict.makeConflictCopy(server: server, date: fixedDate, newId: "new-uuid")
        XCTAssertEqual(copy.document.id, "new-uuid")
        XCTAssertNotEqual(copy.document.id, server.id)
    }

    func test_makeConflictCopy_titleIsSuffixedWithDate() {
        let server = doc("d1", title: "Trip Plan")
        let copy = DocumentSyncConflict.makeConflictCopy(server: server, date: fixedDate, newId: "n1")
        XCTAssertEqual(copy.document.title, "Trip Plan (conflicted copy 2026-08-02)")
    }

    func test_makeConflictCopy_carriesServerContentFolderAndVisibility() {
        let server = doc("d1", title: "T", content: "server body",
                         folderId: "f9", isPublic: true, updatedAt: "2026-08-02T00:00:00Z")
        let copy = DocumentSyncConflict.makeConflictCopy(server: server, date: fixedDate, newId: "n1")
        XCTAssertEqual(copy.document.content, "server body")
        XCTAssertEqual(copy.document.folderId, "f9")
        XCTAssertEqual(copy.document.isPublic, true)
    }

    func test_makeConflictCopy_emitsCreateOpMatchingCopy() {
        let server = doc("d1", title: "T", content: "body", folderId: "f9",
                         isPublic: false, updatedAt: "2026-08-02T00:00:00Z")
        let copy = DocumentSyncConflict.makeConflictCopy(server: server, date: fixedDate, newId: "n1")
        XCTAssertEqual(copy.operation.op, .create)
        XCTAssertEqual(copy.operation.type, .document)
        XCTAssertEqual(copy.operation.data.id, "n1")
        XCTAssertEqual(copy.operation.data.title, copy.document.title)
        XCTAssertEqual(copy.operation.data.content, "body")
        XCTAssertEqual(copy.operation.data.folderId, "f9")
        XCTAssertEqual(copy.operation.data.isPublic, false)
    }

    func test_makeConflictCopy_opCarriesNonEmptyRelativePath() {
        // The sync POST silently drops a create op without a relativePath, so the
        // copy must carry one (and the copy document mirrors it).
        let server = doc("d1", title: "T", updatedAt: "2026-08-02T00:00:00Z")
        let copy = DocumentSyncConflict.makeConflictCopy(server: server, date: fixedDate, newId: "n1")
        XCTAssertEqual(copy.operation.data.relativePath?.isEmpty, false)
        XCTAssertEqual(copy.document.relativePath, copy.operation.data.relativePath)
    }

    func test_conflictCopyTitle_isDeterministicForDate() {
        XCTAssertEqual(
            DocumentSyncConflict.conflictCopyTitle(original: "X", date: fixedDate),
            "X (conflicted copy 2026-08-02)")
    }
}
