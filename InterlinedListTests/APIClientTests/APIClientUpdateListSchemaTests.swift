import XCTest
@testable import InterlinedList

final class APIClientUpdateListSchemaTests: XCTestCase {
    var sut: APIClient!
    var session: MockURLSession!

    private let okPropertiesJSON = #"""
    {"properties":[
      {"id":"p1","propertyKey":"title","propertyName":"Title","propertyType":"text","displayOrder":0,"isVisible":true,"isRequired":true,"defaultValue":null,"helpText":null,"placeholder":null},
      {"id":"p2","propertyKey":"author","propertyName":"Author","propertyType":"text","displayOrder":1,"isVisible":true,"isRequired":false,"defaultValue":null,"helpText":null,"placeholder":null}
    ]}
    """#

    override func setUp() {
        super.setUp()
        session = MockURLSession()
        sut = APIClient(session: session)
        sut.setBearerToken("tok")
    }

    // MARK: HTTP method & path

    func test_updateListSchema_sendsPutToCorrectPath() async throws {
        session.stub(json: okPropertiesJSON)
        _ = try await sut.updateListSchema(listId: "abc", schemaDSL: "Title:text")
        XCTAssertEqual(session.lastRequest?.httpMethod, "PUT")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/lists/abc/schema")
    }

    func test_updateListSchema_includesBearerToken() async throws {
        session.stub(json: okPropertiesJSON)
        _ = try await sut.updateListSchema(listId: "abc", schemaDSL: "Title:text")
        XCTAssertEqual(session.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
    }

    func test_updateListSchema_percentEncodesListId() async throws {
        session.stub(json: okPropertiesJSON)
        // .urlPathAllowed keeps "/" but encodes spaces — consistent with other APIClient methods.
        _ = try await sut.updateListSchema(listId: "abc def", schemaDSL: "Title:text")
        let absolute = session.lastRequest?.url?.absoluteString ?? ""
        XCTAssertTrue(absolute.contains("abc%20def"),
                      "Expected percent-encoded id in URL, got: \(absolute)")
        XCTAssertTrue(absolute.hasSuffix("/schema"), "Expected URL to end with /schema, got: \(absolute)")
    }

    // MARK: Body

    func test_updateListSchema_sendsSchemaKeyInJSONBody() async throws {
        session.stub(json: okPropertiesJSON)
        _ = try await sut.updateListSchema(listId: "abc", schemaDSL: "Title:text, Author:text")
        guard let body = session.lastRequest?.httpBody else {
            return XCTFail("Expected HTTP body")
        }
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        XCTAssertEqual(json?["schema"] as? String, "Title:text, Author:text")
        XCTAssertEqual(json?.keys.count, 1, "Body should only contain a single `schema` key")
    }

    func test_updateListSchema_setsContentTypeHeader() async throws {
        session.stub(json: okPropertiesJSON)
        _ = try await sut.updateListSchema(listId: "abc", schemaDSL: "Title:text")
        XCTAssertEqual(session.lastRequest?.value(forHTTPHeaderField: "Content-Type"), "application/json")
    }

    // MARK: Decoding

    func test_updateListSchema_decodesProperties() async throws {
        session.stub(json: okPropertiesJSON)
        let props = try await sut.updateListSchema(listId: "abc", schemaDSL: "Title:text, Author:text")
        XCTAssertEqual(props.count, 2)
        XCTAssertEqual(props.first?.id, "p1")
        XCTAssertEqual(props.first?.propertyName, "Title")
        XCTAssertEqual(props.first?.propertyType, "text")
        XCTAssertEqual(props.last?.id, "p2")
        XCTAssertEqual(props.last?.propertyName, "Author")
    }

    func test_updateListSchema_missingPropertiesKey_returnsEmpty() async throws {
        session.stub(json: #"{"ok":true}"#)
        let props = try await sut.updateListSchema(listId: "abc", schemaDSL: "Title:text")
        XCTAssertTrue(props.isEmpty)
    }

    func test_updateListSchema_emptyPropertiesArray_returnsEmpty() async throws {
        session.stub(json: #"{"properties":[]}"#)
        let props = try await sut.updateListSchema(listId: "abc", schemaDSL: "Title:text")
        XCTAssertTrue(props.isEmpty)
    }

    func test_updateListSchema_nullProperties_returnsEmpty() async throws {
        session.stub(json: #"{"properties":null}"#)
        let props = try await sut.updateListSchema(listId: "abc", schemaDSL: "Title:text")
        XCTAssertTrue(props.isEmpty)
    }

    // MARK: Errors

    func test_updateListSchema_401_throwsStatusError() async throws {
        session.stub(data: Data(), statusCode: 401)
        do {
            _ = try await sut.updateListSchema(listId: "abc", schemaDSL: "Title:text")
            XCTFail("Expected throw")
        } catch APIError.status(let code) {
            XCTAssertEqual(code, 401)
        }
    }

    func test_updateListSchema_serverErrorJSON_throwsServerError() async throws {
        session.stub(json: #"{"error":"invalid schema"}"#, statusCode: 422)
        do {
            _ = try await sut.updateListSchema(listId: "abc", schemaDSL: "bogus")
            XCTFail("Expected throw")
        } catch APIError.server(let msg) {
            XCTAssertEqual(msg, "invalid schema")
        }
    }
}
