import XCTest
@testable import InterlinedList

final class APIClientListFolderTests: XCTestCase {
    var sut: APIClient!
    var session: MockURLSession!

    private let folderJSON = #"{"id":"f1","name":"My Folder","created_at":"2024-01-01T00:00:00Z"}"#
    private let listJSON = #"{"id":"l1","title":"My List","created_at":"2024-01-01T00:00:00Z"}"#

    override func setUp() {
        super.setUp()
        session = MockURLSession()
        sut = APIClient(session: session)
        sut.setBearerToken("tok")
    }

    // MARK: createListFolder()

    func test_createListFolder_sendsPostToCorrectPath() async throws {
        session.stub(json: #"{"folder":\#(folderJSON)}"#)
        _ = try await sut.createListFolder(name: "My Folder", parentId: nil)
        XCTAssertEqual(session.lastRequest?.httpMethod, "POST")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/folders")
    }

    func test_createListFolder_sendsBearerToken() async throws {
        session.stub(json: #"{"folder":\#(folderJSON)}"#)
        _ = try await sut.createListFolder(name: "My Folder", parentId: nil)
        XCTAssertEqual(session.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
    }

    func test_createListFolder_bodyContainsName() async throws {
        session.stub(json: #"{"folder":\#(folderJSON)}"#)
        _ = try await sut.createListFolder(name: "My Folder", parentId: nil)
        let body = try XCTUnwrap(session.lastRequest?.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["name"] as? String, "My Folder")
    }

    func test_createListFolder_withParentId_sendsParentId() async throws {
        session.stub(json: #"{"folder":\#(folderJSON)}"#)
        _ = try await sut.createListFolder(name: "Child", parentId: "parent-123")
        let body = try XCTUnwrap(session.lastRequest?.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["parent_id"] as? String, "parent-123")
    }

    func test_createListFolder_decodesReturnedFolder() async throws {
        session.stub(json: #"{"folder":\#(folderJSON)}"#)
        let folder = try await sut.createListFolder(name: "My Folder", parentId: nil)
        XCTAssertEqual(folder.id, "f1")
        XCTAssertEqual(folder.name, "My Folder")
    }

    func test_createListFolder_401_throwsStatusError() async throws {
        session.stub(data: Data(), statusCode: 401)
        do {
            _ = try await sut.createListFolder(name: "X", parentId: nil)
            XCTFail("Expected throw")
        } catch APIError.status(let code) {
            XCTAssertEqual(code, 401)
        }
    }

    func test_createListFolder_serverError_throwsServerError() async throws {
        session.stub(json: #"{"error":"name required"}"#, statusCode: 422)
        do {
            _ = try await sut.createListFolder(name: "", parentId: nil)
            XCTFail("Expected throw")
        } catch APIError.server(let msg) {
            XCTAssertEqual(msg, "name required")
        }
    }

    func test_createListFolder_subscriberOnly403_surfacesServerMessageVerbatim() async throws {
        let message = "Subscriber only feature"
        session.stub(json: #"{"error":"\#(message)"}"#, statusCode: 403)
        do {
            _ = try await sut.createListFolder(name: "X", parentId: nil)
            XCTFail("Expected throw")
        } catch APIError.server(let msg) {
            XCTAssertEqual(msg, message)
        } catch {
            XCTFail("Expected APIError.server, got \(error)")
        }
    }

    // MARK: updateListFolder()

    func test_updateListFolder_sendsPutToCorrectPath() async throws {
        session.stub(json: #"{"folder":\#(folderJSON)}"#)
        _ = try await sut.updateListFolder(id: "f1", name: "Renamed", parentId: nil)
        XCTAssertEqual(session.lastRequest?.httpMethod, "PUT")
        XCTAssertTrue(session.lastRequest?.url?.path.hasSuffix("/api/folders/f1") == true)
    }

    func test_updateListFolder_bodyContainsName() async throws {
        session.stub(json: #"{"folder":\#(folderJSON)}"#)
        _ = try await sut.updateListFolder(id: "f1", name: "Renamed", parentId: nil)
        let body = try XCTUnwrap(session.lastRequest?.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["name"] as? String, "Renamed")
    }

    func test_updateListFolder_withParentId_sendsParentId() async throws {
        session.stub(json: #"{"folder":\#(folderJSON)}"#)
        _ = try await sut.updateListFolder(id: "f1", name: nil, parentId: "p1")
        let body = try XCTUnwrap(session.lastRequest?.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["parent_id"] as? String, "p1")
    }

    func test_updateListFolder_409_throwsStatusError() async throws {
        session.stub(data: Data(), statusCode: 409)
        do {
            _ = try await sut.updateListFolder(id: "f1", name: "Clash", parentId: nil)
            XCTFail("Expected throw")
        } catch APIError.status(let code) {
            XCTAssertEqual(code, 409)
        }
    }

    func test_updateListFolder_decodesReturnedFolder() async throws {
        session.stub(json: #"{"folder":\#(folderJSON)}"#)
        let folder = try await sut.updateListFolder(id: "f1", name: "My Folder", parentId: nil)
        XCTAssertEqual(folder.id, "f1")
    }

    // MARK: deleteListFolder()

    func test_deleteListFolder_sendsDeleteToCorrectPath() async throws {
        session.stub(data: Data(), statusCode: 200)
        try await sut.deleteListFolder(id: "f1")
        XCTAssertEqual(session.lastRequest?.httpMethod, "DELETE")
        XCTAssertTrue(session.lastRequest?.url?.path.hasSuffix("/api/folders/f1") == true)
    }

    func test_deleteListFolder_sendsBearerToken() async throws {
        session.stub(data: Data(), statusCode: 200)
        try await sut.deleteListFolder(id: "f1")
        XCTAssertEqual(session.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
    }

    func test_deleteListFolder_percentEncodesId() async throws {
        session.stub(data: Data(), statusCode: 200)
        try await sut.deleteListFolder(id: "f 1")
        let path = session.lastRequest?.url?.path ?? ""
        XCTAssertTrue(path.hasSuffix("/api/folders/f%201") || path.hasSuffix("/api/folders/f 1"),
                      "Expected percent-encoded path, got: \(path)")
    }

    func test_deleteListFolder_401_throwsStatusError() async throws {
        session.stub(data: Data(), statusCode: 401)
        do {
            try await sut.deleteListFolder(id: "f1")
            XCTFail("Expected throw")
        } catch APIError.status(let code) {
            XCTAssertEqual(code, 401)
        }
    }

    // MARK: updateList()

    func test_updateList_sendsPutToCorrectPath() async throws {
        session.stub(json: #"{"list":\#(listJSON)}"#)
        _ = try await sut.updateList(id: "l1", title: "New Name", description: nil, isPublic: nil)
        XCTAssertEqual(session.lastRequest?.httpMethod, "PUT")
        XCTAssertTrue(session.lastRequest?.url?.path.hasSuffix("/api/lists/l1") == true)
    }

    func test_updateList_sendsBearerToken() async throws {
        session.stub(json: #"{"list":\#(listJSON)}"#)
        _ = try await sut.updateList(id: "l1", title: "X", description: nil, isPublic: nil)
        XCTAssertEqual(session.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
    }

    func test_updateList_bodyContainsTitle() async throws {
        session.stub(json: #"{"list":\#(listJSON)}"#)
        _ = try await sut.updateList(id: "l1", title: "Renamed", description: "Desc", isPublic: true)
        let body = try XCTUnwrap(session.lastRequest?.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["title"] as? String, "Renamed")
        XCTAssertEqual(json["description"] as? String, "Desc")
        XCTAssertEqual(json["is_public"] as? Bool, true)
    }

    func test_updateList_bodyContainsIsPublic() async throws {
        session.stub(json: #"{"list":\#(listJSON)}"#)
        _ = try await sut.updateList(id: "l1", title: "T", description: nil, isPublic: true)
        let body = try XCTUnwrap(session.lastRequest?.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["is_public"] as? Bool, true)
    }

    func test_updateList_bodyContainsDescription() async throws {
        session.stub(json: #"{"list":\#(listJSON)}"#)
        _ = try await sut.updateList(id: "l1", title: "T", description: "My Desc", isPublic: nil)
        let body = try XCTUnwrap(session.lastRequest?.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["description"] as? String, "My Desc")
    }

    func test_updateList_decodesReturnedList() async throws {
        session.stub(json: #"{"list":\#(listJSON)}"#)
        let list = try await sut.updateList(id: "l1", title: "My List", description: nil, isPublic: nil)
        XCTAssertEqual(list.id, "l1")
        XCTAssertEqual(list.name, "My List")
    }

    func test_updateList_401_throwsStatusError() async throws {
        session.stub(data: Data(), statusCode: 401)
        do {
            _ = try await sut.updateList(id: "l1", title: "X", description: nil, isPublic: nil)
            XCTFail("Expected throw")
        } catch APIError.status(let code) {
            XCTAssertEqual(code, 401)
        }
    }

    func test_updateList_serverError_propagates() async throws {
        session.stub(json: #"{"error":"forbidden"}"#, statusCode: 403)
        do {
            _ = try await sut.updateList(id: "l1", title: "X", description: nil, isPublic: nil)
            XCTFail("Expected throw")
        } catch APIError.server(let msg) {
            XCTAssertEqual(msg, "forbidden")
        }
    }

    // MARK: searchLists()

    func test_searchLists_sendsGetToCorrectPath() async throws {
        session.stub(json: #"{"lists":[],"pagination":null}"#)
        _ = try await sut.searchLists(q: "books")
        XCTAssertEqual(session.lastRequest?.httpMethod, "GET")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/lists/search")
    }

    func test_searchLists_includesQueryParam() async throws {
        session.stub(json: #"{"lists":[],"pagination":null}"#)
        _ = try await sut.searchLists(q: "books")
        let url = session.lastRequest?.url?.absoluteString ?? ""
        XCTAssertTrue(url.contains("q=books"), "Expected q=books in \(url)")
    }

    func test_searchLists_includesLimitAndOffset() async throws {
        session.stub(json: #"{"lists":[],"pagination":null}"#)
        _ = try await sut.searchLists(q: "q", limit: 5, offset: 10)
        let url = session.lastRequest?.url?.absoluteString ?? ""
        XCTAssertTrue(url.contains("limit=5"), "Expected limit=5 in \(url)")
        XCTAssertTrue(url.contains("offset=10"), "Expected offset=10 in \(url)")
    }

    func test_searchLists_decodesResults() async throws {
        session.stub(json: #"{"lists":[\#(listJSON)],"pagination":null}"#)
        let (lists, _) = try await sut.searchLists(q: "my")
        XCTAssertEqual(lists.count, 1)
        XCTAssertEqual(lists.first?.name, "My List")
    }

    func test_searchLists_decodesPagination() async throws {
        session.stub(json: #"{"lists":[],"pagination":{"total":42,"limit":20,"offset":0,"hasMore":true}}"#)
        let (_, pagination) = try await sut.searchLists(q: "q")
        XCTAssertEqual(pagination?.total, 42)
        XCTAssertEqual(pagination?.hasMore, true)
    }

    func test_searchLists_401_throwsStatusError() async throws {
        session.stub(data: Data(), statusCode: 401)
        do {
            _ = try await sut.searchLists(q: "q")
            XCTFail("Expected throw")
        } catch APIError.status(let code) {
            XCTAssertEqual(code, 401)
        }
    }

    func test_searchLists_percentEncodesQuery() async throws {
        session.stub(json: #"{"lists":[],"pagination":null}"#)
        _ = try await sut.searchLists(q: "hello world")
        let url = session.lastRequest?.url?.absoluteString ?? ""
        XCTAssertTrue(url.contains("hello"), "Expected 'hello' in \(url)")
    }
}
