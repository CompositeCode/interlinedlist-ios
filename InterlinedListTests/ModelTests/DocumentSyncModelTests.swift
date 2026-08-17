import XCTest
@testable import InterlinedList

final class DocumentSyncModelTests: XCTestCase {
    private let snakeDecoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    // MARK: - New Document / DocumentFolder fields

    func test_document_decodesDeletedAt() throws {
        let json = #"{"id":"d1","title":"Gone","deleted_at":"2026-07-31T00:00:00Z"}"#
        let d = try snakeDecoder.decode(Document.self, from: Data(json.utf8))
        XCTAssertEqual(d.deletedAt, "2026-07-31T00:00:00Z")
    }

    func test_document_missingDeletedAt_isNil() throws {
        let json = #"{"id":"d1","title":"Live"}"#
        let d = try snakeDecoder.decode(Document.self, from: Data(json.utf8))
        XCTAssertNil(d.deletedAt)
    }

    func test_documentFolder_decodesUpdatedAtAndDeletedAt() throws {
        let json = #"{"id":"f1","name":"F","parent_id":null,"updated_at":"2026-07-30T00:00:00Z","deleted_at":"2026-07-31T00:00:00Z"}"#
        let f = try snakeDecoder.decode(DocumentFolder.self, from: Data(json.utf8))
        XCTAssertEqual(f.updatedAt, "2026-07-30T00:00:00Z")
        XCTAssertEqual(f.deletedAt, "2026-07-31T00:00:00Z")
    }

    func test_documentFolder_legacyCacheWithoutNewKeys_stillDecodes() throws {
        // A cache written before the new fields existed must still decode (fields absent).
        let json = #"{"id":"f1","name":"Legacy","parent_id":"p1"}"#
        let f = try snakeDecoder.decode(DocumentFolder.self, from: Data(json.utf8))
        XCTAssertEqual(f.parentId, "p1")
        XCTAssertNil(f.updatedAt)
        XCTAssertNil(f.deletedAt)
    }

    // MARK: - DocumentSyncResponse

    func test_syncResponse_decodesCamelCaseBody() throws {
        // The /sync endpoint returns camelCase; the response still decodes with the
        // snake-case-converting decoder because camelCase keys pass through unchanged.
        let json = #"""
        {"folders":[{"id":"f1","name":"F"}],
         "documents":[{"id":"d1","title":"D"}],
         "lastSyncAt":"2026-07-31T00:00:00Z"}
        """#
        let r = try snakeDecoder.decode(DocumentSyncResponse.self, from: Data(json.utf8))
        XCTAssertEqual(r.folders.count, 1)
        XCTAssertEqual(r.documents.count, 1)
        XCTAssertEqual(r.lastSyncAt, "2026-07-31T00:00:00Z")
    }

    func test_syncResponse_absentArrays_defaultEmpty() throws {
        let json = #"{"lastSyncAt":"2026-07-31T00:00:00Z"}"#
        let r = try snakeDecoder.decode(DocumentSyncResponse.self, from: Data(json.utf8))
        XCTAssertTrue(r.folders.isEmpty)
        XCTAssertTrue(r.documents.isEmpty)
    }

    // MARK: - DocumentSyncState round-trip

    func test_syncState_roundTrip_preservesFieldsAndCursor() throws {
        let state = DocumentSyncState(
            folders: [DocumentFolder(id: "f1", name: "F", parentId: "p1", updatedAt: "2026-07-30T00:00:00Z")],
            documents: [Document(id: "d1", title: "D", content: "x", folderId: "f1", isPublic: true,
                                  createdAt: "2026-07-01T00:00:00Z", updatedAt: "2026-07-30T00:00:00Z")],
            lastSyncAt: "2026-07-31T00:00:00Z"
        )
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(DocumentSyncState.self, from: data)
        XCTAssertEqual(decoded.lastSyncAt, "2026-07-31T00:00:00Z")
        XCTAssertEqual(decoded.folders.first?.id, "f1")
        XCTAssertEqual(decoded.folders.first?.updatedAt, "2026-07-30T00:00:00Z")
        XCTAssertEqual(decoded.documents.first?.id, "d1")
        XCTAssertEqual(decoded.documents.first?.folderId, "f1")
        XCTAssertEqual(decoded.documents.first?.isPublic, true)
    }

    func test_syncState_emptyRoundTrip() throws {
        let state = DocumentSyncState()
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(DocumentSyncState.self, from: data)
        XCTAssertTrue(decoded.folders.isEmpty)
        XCTAssertTrue(decoded.documents.isEmpty)
        XCTAssertNil(decoded.lastSyncAt)
        XCTAssertTrue(decoded.outbox.isEmpty)
        XCTAssertTrue(decoded.localStates.isEmpty)
    }

    // MARK: - Slice 2: outbox + localStates persistence

    func test_syncState_withOutboxAndStates_roundTrips() throws {
        var state = DocumentSyncState(documents: [Document(id: "d1", title: "D")], lastSyncAt: "c1")
        state.outbox = [
            SyncOperation(op: .create, type: .document,
                          data: SyncOpData(id: "d1", title: "D", content: "x", isPublic: false)),
            SyncOperation(op: .delete, type: .folder, data: SyncOpData(id: "f9")),
        ]
        state.localStates = ["d1": .dirty, "f9": .deleted]
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(DocumentSyncState.self, from: data)
        XCTAssertEqual(decoded.outbox.count, 2)
        XCTAssertEqual(decoded.outbox.first?.op, .create)
        XCTAssertEqual(decoded.outbox.first?.data.content, "x")
        XCTAssertEqual(decoded.outbox.last?.type, .folder)
        XCTAssertEqual(decoded.localStates["d1"], .dirty)
        XCTAssertEqual(decoded.localStates["f9"], .deleted)
    }

    func test_syncState_slice1CacheWithoutOutbox_stillDecodes() throws {
        // A cache written by Slice 1 has no outbox/localStates keys.
        let json = #"{"folders":[],"documents":[{"id":"d1","title":"D"}],"lastSyncAt":"c1"}"#
        let decoded = try JSONDecoder().decode(DocumentSyncState.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.documents.first?.id, "d1")
        XCTAssertTrue(decoded.outbox.isEmpty)
        XCTAssertTrue(decoded.localStates.isEmpty)
    }

    // MARK: - Slice 3: baselines persistence

    func test_syncState_baselinesRoundTrip() throws {
        var state = DocumentSyncState(documents: [Document(id: "d1", title: "D")], lastSyncAt: "c1")
        state.baselines = ["d1": "2026-08-01T00:00:00Z", "d2": "2026-08-02T00:00:00Z"]
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(DocumentSyncState.self, from: data)
        XCTAssertEqual(decoded.baselines["d1"], "2026-08-01T00:00:00Z")
        XCTAssertEqual(decoded.baselines["d2"], "2026-08-02T00:00:00Z")
    }

    func test_syncState_slice2CacheWithoutBaselines_stillDecodes() throws {
        // A Slice-1/2 cache has no baselines key.
        let json = #"{"folders":[],"documents":[{"id":"d1","title":"D"}],"lastSyncAt":"c1","outbox":[],"localStates":{}}"#
        let decoded = try JSONDecoder().decode(DocumentSyncState.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.documents.first?.id, "d1")
        XCTAssertTrue(decoded.baselines.isEmpty)
    }

    // MARK: - SyncConflictNotice

    func test_syncConflictNotice_equatableByFields() {
        let a = SyncConflictNotice(id: "d1", originalTitle: "Live", copyTitle: "Live (conflicted copy 2026-08-02)")
        let b = SyncConflictNotice(id: "d1", originalTitle: "Live", copyTitle: "Live (conflicted copy 2026-08-02)")
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.id, "d1")
    }

    // MARK: - SyncOpData encodes only non-nil keys

    func test_syncOpData_deleteEncodesOnlyId() throws {
        let data = SyncOpData(id: "d1")
        let json = try JSONEncoder().encode(data)
        let obj = try JSONSerialization.jsonObject(with: json) as? [String: Any]
        XCTAssertEqual(obj?.keys.sorted(), ["id"])
        XCTAssertEqual(obj?["id"] as? String, "d1")
    }

    func test_syncOpData_encodesCamelCaseAndDropsNilKeys() throws {
        let data = SyncOpData(id: "d1", folderId: "f1", title: "T", content: "C", isPublic: true)
        let json = try JSONEncoder().encode(data)
        let obj = try JSONSerialization.jsonObject(with: json) as? [String: Any]
        XCTAssertEqual(obj?["folderId"] as? String, "f1")
        XCTAssertEqual(obj?["title"] as? String, "T")
        XCTAssertEqual(obj?["isPublic"] as? Bool, true)
        // Untouched fields are absent, not null.
        XCTAssertNil(obj?["name"])
        XCTAssertNil(obj?["parentId"])
        XCTAssertNil(obj?["relativePath"])
    }

    func test_syncOperation_encodesCamelCaseOpTypeAndData() throws {
        let op = SyncOperation(op: .create, type: .document, path: "notes.md",
                               data: SyncOpData(id: "d1", title: "Notes"))
        let json = try JSONEncoder().encode(op)
        let obj = try JSONSerialization.jsonObject(with: json) as? [String: Any]
        XCTAssertEqual(obj?["op"] as? String, "create")
        XCTAssertEqual(obj?["type"] as? String, "document")
        XCTAssertEqual(obj?["path"] as? String, "notes.md")
        let dataObj = obj?["data"] as? [String: Any]
        XCTAssertEqual(dataObj?["id"] as? String, "d1")
        XCTAssertEqual(dataObj?["title"] as? String, "Notes")
    }
}
