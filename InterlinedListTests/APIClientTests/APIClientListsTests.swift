import XCTest
@testable import InterlinedList

final class APIClientListsTests: XCTestCase {
    var sut: APIClient!
    var session: MockURLSession!

    private let listJSON = #"{"id":"l1","title":"My List","created_at":"2024-01-01T00:00:00Z"}"#

    override func setUp() {
        super.setUp()
        session = MockURLSession()
        sut = APIClient(session: session)
        sut.setBearerToken("tok")
    }

    // MARK: lists()

    func test_lists_sendsGetToCorrectPath() async throws {
        session.stub(json: #"{"lists":[\#(listJSON)]}"#)
        _ = try await sut.lists()
        XCTAssertEqual(session.lastRequest?.httpMethod, "GET")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/lists")
    }

    func test_lists_decodesLists() async throws {
        session.stub(json: #"{"lists":[\#(listJSON)]}"#)
        let lists = try await sut.lists()
        XCTAssertEqual(lists.count, 1)
        XCTAssertEqual(lists.first?.name, "My List")
    }

    func test_lists_401_throws() async throws {
        session.stub(data: Data(), statusCode: 401)
        do {
            _ = try await sut.lists()
            XCTFail("Expected throw from lists call")
        } catch APIError.status(let code) {
            XCTAssertEqual(code, 401)
        }
    }

    // MARK: createList()

    func test_createList_sendsPostToCorrectPath() async throws {
        session.stub(json: #"{"data":\#(listJSON)}"#)
        _ = try await sut.createList(title: "New", description: nil, isPublic: true)
        XCTAssertEqual(session.lastRequest?.httpMethod, "POST")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/lists")
    }

    func test_createList_decodesListFromDataKey() async throws {
        session.stub(json: #"{"message":"List created successfully","data":\#(listJSON)}"#)
        let list = try await sut.createList(title: "New", description: nil, isPublic: true)
        XCTAssertEqual(list.id, "l1")
        XCTAssertEqual(list.name, "My List")
    }

    func test_createList_bodyContainsTitle() async throws {
        session.stub(json: #"{"data":\#(listJSON)}"#)
        _ = try await sut.createList(title: "My List", description: "Desc", isPublic: false)
        let body = try XCTUnwrap(session.lastRequest?.httpBody)
        let json = try XCTUnwrap(try? JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["title"] as? String, "My List")
        XCTAssertEqual(json["isPublic"] as? Bool, false)
    }

    func test_createList_withSchema_sendsDSLObjectInBody() async throws {
        session.stub(json: #"{"data":\#(listJSON)}"#)
        let schema = ListSchemaDSL(name: "My List", description: nil, fields: [
            .init(key: "title", label: "Title", type: "text", displayOrder: 0, required: false, visible: true),
            .init(key: "author", label: "Author", type: "text", displayOrder: 1, required: false, visible: true),
        ])
        _ = try await sut.createList(title: "My List", description: nil, isPublic: true, schema: schema)
        let body = try XCTUnwrap(session.lastRequest?.httpBody)
        let json = try XCTUnwrap(try? JSONSerialization.jsonObject(with: body) as? [String: Any])
        let sentSchema = try XCTUnwrap(json["schema"] as? [String: Any],
                                       "schema must be an object, not a DSL string")
        XCTAssertEqual(sentSchema["name"] as? String, "My List")
        let fields = try XCTUnwrap(sentSchema["fields"] as? [[String: Any]])
        XCTAssertEqual(fields.count, 2)
        XCTAssertEqual(fields.first?["key"] as? String, "title")
        XCTAssertEqual(fields.first?["label"] as? String, "Title")
        XCTAssertEqual(fields.first?["type"] as? String, "text")
    }

    func test_createList_withoutSchema_omitsSchemaKey() async throws {
        session.stub(json: #"{"data":\#(listJSON)}"#)
        _ = try await sut.createList(title: "My List", description: nil, isPublic: true)
        let body = try XCTUnwrap(session.lastRequest?.httpBody)
        let json = try XCTUnwrap(try? JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertNil(json["schema"], "Nil schema should be omitted from the request body")
    }

    func test_createList_401_throws() async throws {
        session.stub(data: Data(), statusCode: 401)
        do {
            _ = try await sut.createList(title: "X", description: nil, isPublic: true)
            XCTFail("Expected throw")
        } catch APIError.status(let code) {
            XCTAssertEqual(code, 401)
        }
    }

    // MARK: deleteList()

    func test_deleteList_sendsDeleteToCorrectPath() async throws {
        session.stub(data: Data(), statusCode: 204)
        try await sut.deleteList(id: "l1")
        XCTAssertEqual(session.lastRequest?.httpMethod, "DELETE")
        XCTAssertTrue(session.lastRequest?.url?.path.hasSuffix("/api/lists/l1") == true)
    }

    func test_deleteList_sendsBearerToken() async throws {
        session.stub(data: Data(), statusCode: 204)
        try await sut.deleteList(id: "l1")
        XCTAssertEqual(session.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
    }

    // MARK: updateList() — isPublic round-trip
    //
    // The backend PUT /api/lists/:id reads camelCase (`isPublic`) from the body, so
    // updateList uses the camelCase encoder. Sending snake_case (`is_public`) left
    // the field `undefined` server-side and the update was silently dropped — hence
    // these assert the camelCase key.

    func test_updateList_isPublicTrue_sentAsCamelCaseBoolAndDecodes() async throws {
        let body = #"{"list":{"id":"l1","title":"My List","isPublic":true,"createdAt":"2024-01-01T00:00:00Z"}}"#
        session.stub(json: body)
        let updated = try await sut.updateList(id: "l1", title: "My List", description: nil, isPublic: true)

        XCTAssertEqual(session.lastRequest?.httpMethod, "PUT")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/lists/l1")

        let sentBody = try XCTUnwrap(session.lastRequest?.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: sentBody) as? [String: Any])
        XCTAssertEqual(json["isPublic"] as? Bool, true)
        XCTAssertNil(json["is_public"], "Must send camelCase, not snake_case")

        XCTAssertEqual(updated.id, "l1")
        XCTAssertEqual(updated.isPublic, true)
    }

    func test_updateList_isPublicFalse_sentAsCamelCaseBoolAndDecodes() async throws {
        let body = #"{"list":{"id":"l1","title":"My List","isPublic":false,"createdAt":"2024-01-01T00:00:00Z"}}"#
        session.stub(json: body)
        let updated = try await sut.updateList(id: "l1", title: "My List", description: nil, isPublic: false)

        XCTAssertEqual(session.lastRequest?.httpMethod, "PUT")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/lists/l1")

        let sentBody = try XCTUnwrap(session.lastRequest?.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: sentBody) as? [String: Any])
        XCTAssertEqual(json["isPublic"] as? Bool, false)

        XCTAssertEqual(updated.id, "l1")
        XCTAssertEqual(updated.isPublic, false)
    }
}
