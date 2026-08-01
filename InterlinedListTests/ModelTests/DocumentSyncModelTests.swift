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
    }
}
