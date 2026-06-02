import XCTest
@testable import InterlinedList

final class DocumentCodableTests: XCTestCase {
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    func test_decode_allFields() throws {
        let json = #"""
        {"id":"d1","title":"My Doc","content":"# Hello","folder_id":"f1",
         "is_public":true,"created_at":"2024-01-01T00:00:00Z","updated_at":"2024-01-02T00:00:00Z"}
        """#
        let d = try decoder.decode(Document.self, from: Data(json.utf8))
        XCTAssertEqual(d.id, "d1")
        XCTAssertEqual(d.title, "My Doc")
        XCTAssertEqual(d.content, "# Hello")
        XCTAssertEqual(d.folderId, "f1")
        XCTAssertEqual(d.isPublic, true)
    }

    func test_decode_optionalFieldsAbsent() throws {
        let json = #"{"id":"d2","title":"Empty"}"#
        let d = try decoder.decode(Document.self, from: Data(json.utf8))
        XCTAssertNil(d.content)
        XCTAssertNil(d.folderId)
        XCTAssertNil(d.isPublic)
    }

    func test_decode_documentsResponse() throws {
        let json = #"{"documents":[{"id":"d1","title":"A"},{"id":"d2","title":"B"}]}"#
        let r = try decoder.decode(DocumentsResponse.self, from: Data(json.utf8))
        XCTAssertEqual(r.documents.count, 2)
    }
}

final class DocumentFolderCodableTests: XCTestCase {
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    func test_decode_withParent() throws {
        let json = #"{"id":"f1","name":"Projects","parent_id":"f0"}"#
        let f = try decoder.decode(DocumentFolder.self, from: Data(json.utf8))
        XCTAssertEqual(f.id, "f1")
        XCTAssertEqual(f.name, "Projects")
        XCTAssertEqual(f.parentId, "f0")
    }

    func test_decode_rootFolder_nilParent() throws {
        let json = #"{"id":"f1","name":"Root","parent_id":null}"#
        let f = try decoder.decode(DocumentFolder.self, from: Data(json.utf8))
        XCTAssertNil(f.parentId)
    }

    func test_decode_foldersResponse() throws {
        let json = #"{"folders":[{"id":"f1","name":"A"},{"id":"f2","name":"B"}]}"#
        let r = try decoder.decode(DocumentFoldersResponse.self, from: Data(json.utf8))
        XCTAssertEqual(r.folders.count, 2)
    }
}
