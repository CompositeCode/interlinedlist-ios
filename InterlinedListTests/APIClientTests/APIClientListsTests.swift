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

    // MARK: list data rows — add / update / close
    //
    // The row endpoints return the saved row under `data` (not `row`) and wrap the
    // request row under `data`. GitHub-backed lists reuse these exact routes: the
    // backend proxies POST→create issue, PUT→patch issue (path id = issue number),
    // DELETE→close issue. These guard the `row`→`data` decode fix and the payload
    // shape the GitHub proxy requires (a FULL row incl. title on every update).

    private let rowJSON = #"{"id":"42","rowData":{"title":"Fix login crash","state":"open"},"createdAt":"2024-01-01T00:00:00Z"}"#

    func test_addListItem_postsToDataPath_wrapsRowUnderData() async throws {
        session.stub(json: #"{"message":"Row created successfully","data":\#(rowJSON)}"#, statusCode: 201)
        _ = try await sut.addListItem(listId: "l1", rowData: ["title": .string("Fix login crash"), "state": .string("open")])

        XCTAssertEqual(session.lastRequest?.httpMethod, "POST")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/lists/l1/data")

        let body = try XCTUnwrap(session.lastRequest?.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let data = try XCTUnwrap(json["data"] as? [String: Any], "row must be wrapped under `data`")
        XCTAssertEqual(data["title"] as? String, "Fix login crash")
        XCTAssertEqual(data["state"] as? String, "open")
    }

    func test_addListItem_decodesRowFromDataKey() async throws {
        session.stub(json: #"{"message":"Row created successfully","data":\#(rowJSON)}"#, statusCode: 201)
        let item = try await sut.addListItem(listId: "l1", rowData: ["title": .string("Fix login crash")])
        // Guards the row→data fix: previously this decoded `{row}` and threw noData.
        XCTAssertEqual(item.id, "42")
        XCTAssertEqual(item.rowData["title"], .string("Fix login crash"))
        XCTAssertEqual(item.rowData["state"], .string("open"))
    }

    func test_updateItem_putsFullRowToIssueNumberPath() async throws {
        session.stub(json: #"{"message":"Row updated successfully","data":{"id":"42","rowData":{"title":"Fix login crash","state":"closed"}}}"#)
        let item = try await sut.updateItem(
            listId: "l1",
            itemId: "42",
            rowData: ["title": .string("Fix login crash"), "state": .string("closed")]
        )

        XCTAssertEqual(session.lastRequest?.httpMethod, "PUT")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/lists/l1/data/42")

        // The GitHub proxy rebuilds the issue from the request alone, so the full
        // row (incl. title) must be sent or the title would be blanked to "Untitled".
        let body = try XCTUnwrap(session.lastRequest?.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let data = try XCTUnwrap(json["data"] as? [String: Any])
        XCTAssertEqual(data["title"] as? String, "Fix login crash")
        XCTAssertEqual(data["state"] as? String, "closed")

        XCTAssertEqual(item.rowData["state"], .string("closed"))
    }

    func test_deleteListItem_sendsDeleteToRowPath() async throws {
        session.stub(json: #"{"message":"Row deleted successfully"}"#)
        try await sut.deleteListItem(listId: "l1", itemId: "42")
        XCTAssertEqual(session.lastRequest?.httpMethod, "DELETE")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/lists/l1/data/42")
        XCTAssertEqual(session.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
    }

    // MARK: listSchema() — GitHub schema field metadata

    func test_listSchema_decodesReadOnlyAndSelectOptions() async throws {
        let props = """
        [
          {"id":"p1","propertyKey":"number","propertyName":"Issue #","propertyType":"number","displayOrder":0,"isVisible":true,"isRequired":false,"defaultValue":null,"helpText":null,"placeholder":null,"isReadOnly":true},
          {"id":"p2","propertyKey":"state","propertyName":"State","propertyType":"select","displayOrder":3,"isVisible":true,"isRequired":false,"defaultValue":"open","helpText":null,"placeholder":null,"validationRules":{"options":["open","closed"]}}
        ]
        """
        session.stub(json: #"{"data":{"id":"l1","title":"owner/repo","properties":\#(props)}}"#)
        let schema = try await sut.listSchema(listId: "l1")

        let number = try XCTUnwrap(schema.first { $0.propertyKey == "number" })
        XCTAssertTrue(number.isReadOnly)
        XCTAssertEqual(number.selectOptions, [])

        let state = try XCTUnwrap(schema.first { $0.propertyKey == "state" })
        XCTAssertFalse(state.isReadOnly, "fields without isReadOnly default to false")
        XCTAssertEqual(state.selectOptions, ["open", "closed"])
    }

    func test_listSchema_localProperty_defaultsReadOnlyFalseAndNoOptions() async throws {
        let props = #"[{"id":"p1","propertyKey":"title","propertyName":"Title","propertyType":"text","displayOrder":0,"isVisible":true,"isRequired":true,"defaultValue":null,"helpText":null,"placeholder":null}]"#
        session.stub(json: #"{"data":{"id":"l1","title":"Books","properties":\#(props)}}"#)
        let schema = try await sut.listSchema(listId: "l1")
        let title = try XCTUnwrap(schema.first)
        XCTAssertFalse(title.isReadOnly)
        XCTAssertEqual(title.selectOptions, [])
    }

    /// The backend returns the synthetic GitHub schema in `GET /api/lists/:id`
    /// `properties`, shaped like DB rows (`getGitHubListProperties`): a synthetic
    /// `id` (`gh_<key>`), a `listId`, and a `visibilityCondition` that iOS ignores.
    /// This guards that the real server payload decodes into `ListPropertyDef`.
    func test_listSchema_decodesRealServerGitHubProperties() async throws {
        let props = """
        [
          {"id":"gh_number","listId":"l1","propertyKey":"number","propertyName":"Issue #","propertyType":"number","displayOrder":0,"isRequired":false,"defaultValue":null,"validationRules":null,"helpText":"Auto-assigned by GitHub when the issue is created","placeholder":null,"isVisible":true,"visibilityCondition":null,"isReadOnly":true},
          {"id":"gh_title","listId":"l1","propertyKey":"title","propertyName":"Title","propertyType":"text","displayOrder":1,"isRequired":true,"defaultValue":null,"validationRules":null,"helpText":null,"placeholder":null,"isVisible":true,"visibilityCondition":null,"isReadOnly":false},
          {"id":"gh_state","listId":"l1","propertyKey":"state","propertyName":"State","propertyType":"select","displayOrder":3,"isRequired":false,"defaultValue":"open","validationRules":{"options":["open","closed"]},"helpText":null,"placeholder":null,"isVisible":true,"visibilityCondition":null,"isReadOnly":false}
        ]
        """
        session.stub(json: #"{"data":{"id":"l1","title":"owner/repo","properties":\#(props)}}"#)
        let schema = try await sut.listSchema(listId: "l1")

        let number = try XCTUnwrap(schema.first { $0.propertyKey == "number" })
        XCTAssertEqual(number.id, "gh_number")
        XCTAssertTrue(number.isReadOnly)

        let title = try XCTUnwrap(schema.first { $0.propertyKey == "title" })
        XCTAssertTrue(title.isRequired)
        XCTAssertFalse(title.isReadOnly)

        let state = try XCTUnwrap(schema.first { $0.propertyKey == "state" })
        XCTAssertEqual(state.propertyType, "select")
        XCTAssertEqual(state.selectOptions, ["open", "closed"])
        XCTAssertEqual(state.defaultValue, "open")
    }
}
