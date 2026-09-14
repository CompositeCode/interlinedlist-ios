import XCTest
@testable import InterlinedList

final class APIClientMaterializeTests: XCTestCase {
    var sut: APIClient!
    var session: MockURLSession!

    override func setUp() {
        super.setUp()
        session = MockURLSession()
        sut = APIClient(session: session)
        sut.setBearerToken("tok")
    }

    private let createdJSON = """
    {"list":{"id":"l1","title":"3 messages"},"document":{"id":"d1","title":"3 messages"}}
    """

    private func body() throws -> [String: Any] {
        let data = try XCTUnwrap(session.lastRequest?.httpBody)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private var sampleFields: [MaterializeFieldConfig] {
        [MaterializeFieldConfig(propertyKey: "content", propertyName: "Content", propertyType: "textarea", sourceKey: "content")]
    }

    private var sampleListConfig: MaterializeListConfig {
        MaterializeListConfig(title: "From posts", description: nil, isPublic: false,
                              fields: sampleFields, includeData: true)
    }

    // MARK: - Request shape

    func test_materialize_postsToCorrectPath() async throws {
        session.stub(json: createdJSON, statusCode: 201)
        _ = try await sut.materialize(target: .list, source: .messages(messageIds: ["m1"]),
                                      listConfig: sampleListConfig)
        XCTAssertEqual(session.lastRequest?.httpMethod, "POST")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/materialize")
    }

    func test_materialize_sendsBearerToken() async throws {
        session.stub(json: createdJSON, statusCode: 201)
        _ = try await sut.materialize(target: .list, source: .messages(messageIds: ["m1"]),
                                      listConfig: sampleListConfig)
        XCTAssertEqual(session.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
    }

    /// The whole request is camelCase — a snake_case encoder would send
    /// `list_config` / `message_ids` and the server would reject it.
    func test_materialize_bodyIsCamelCase() async throws {
        session.stub(json: createdJSON, statusCode: 201)
        _ = try await sut.materialize(target: .both, source: .messages(messageIds: ["m1"]),
                                      listConfig: sampleListConfig,
                                      docConfig: MaterializeDocConfig(title: "Doc", relativePath: nil, isPublic: nil,
                                                                      listStyle: nil, rowDataStyle: nil))
        let json = try body()
        XCTAssertNotNil(json["listConfig"])
        XCTAssertNotNil(json["docConfig"])
        XCTAssertNil(json["list_config"])
        let source = try XCTUnwrap(json["source"] as? [String: Any])
        XCTAssertNotNil(source["messageIds"])
        XCTAssertNil(source["message_ids"])
    }

    // MARK: - Source encoding (one shape per kind)

    func test_materialize_messagesSourceEncodesKindAndIds() async throws {
        session.stub(json: createdJSON, statusCode: 201)
        _ = try await sut.materialize(target: .list, source: .messages(messageIds: ["m1", "m2"]),
                                      listConfig: sampleListConfig)
        let source = try XCTUnwrap(try body()["source"] as? [String: Any])
        XCTAssertEqual(source["kind"] as? String, "messages")
        XCTAssertEqual(source["messageIds"] as? [String], ["m1", "m2"])
    }

    func test_materialize_listsSourceEncodesListIds() async throws {
        session.stub(json: createdJSON, statusCode: 201)
        _ = try await sut.materialize(target: .list, source: .lists(listIds: ["l1"]),
                                      listConfig: sampleListConfig)
        let source = try XCTUnwrap(try body()["source"] as? [String: Any])
        XCTAssertEqual(source["kind"] as? String, "lists")
        XCTAssertEqual(source["listIds"] as? [String], ["l1"])
    }

    func test_materialize_rowsSourceEncodesListIdAndRowIds() async throws {
        session.stub(json: createdJSON, statusCode: 201)
        _ = try await sut.materialize(target: .list, source: .rows(listId: "l1", rowIds: ["r1", "r2"]),
                                      listConfig: sampleListConfig)
        let source = try XCTUnwrap(try body()["source"] as? [String: Any])
        XCTAssertEqual(source["kind"] as? String, "rows")
        XCTAssertEqual(source["listId"] as? String, "l1")
        XCTAssertEqual(source["rowIds"] as? [String], ["r1", "r2"])
    }

    func test_materialize_documentSourceEncodesDocumentId() async throws {
        session.stub(json: createdJSON, statusCode: 201)
        _ = try await sut.materialize(target: .doc, source: .document(documentId: "d1"),
                                      docConfig: MaterializeDocConfig(title: "Doc", relativePath: nil, isPublic: nil,
                                                                     listStyle: nil, rowDataStyle: nil))
        let source = try XCTUnwrap(try body()["source"] as? [String: Any])
        XCTAssertEqual(source["kind"] as? String, "document")
        XCTAssertEqual(source["documentId"] as? String, "d1")
    }

    /// Only ids go over the wire — never cell values. The server re-fetches and
    /// re-derives everything, so a request that carried content would be both
    /// wasteful and ignored.
    func test_materialize_sourceCarriesOnlyIds() async throws {
        session.stub(json: createdJSON, statusCode: 201)
        _ = try await sut.materialize(target: .list, source: .messages(messageIds: ["m1"]),
                                      listConfig: sampleListConfig)
        let source = try XCTUnwrap(try body()["source"] as? [String: Any])
        XCTAssertEqual(Set(source.keys), ["kind", "messageIds"])
    }

    // MARK: - Config encoding

    /// A user-added column must send `sourceKey: null`, not omit the key — the
    /// contract documents `string | null` for the mapping.
    func test_materialize_userAddedColumnSendsExplicitNullSourceKey() async throws {
        session.stub(json: createdJSON, statusCode: 201)
        let config = MaterializeListConfig(
            title: "T", description: nil, isPublic: nil,
            fields: [MaterializeFieldConfig(propertyKey: "notes", propertyName: "Notes",
                                            propertyType: "text", sourceKey: nil)],
            includeData: nil
        )
        _ = try await sut.materialize(target: .list, source: .messages(messageIds: ["m1"]), listConfig: config)
        let listConfig = try XCTUnwrap(try body()["listConfig"] as? [String: Any])
        let fields = try XCTUnwrap(listConfig["fields"] as? [[String: Any]])
        XCTAssertTrue(fields[0].keys.contains("sourceKey"))
        XCTAssertTrue(fields[0]["sourceKey"] is NSNull)
    }

    func test_materialize_omitsListConfigForDocOnlyTarget() async throws {
        session.stub(json: createdJSON, statusCode: 201)
        _ = try await sut.materialize(target: .doc, source: .document(documentId: "d1"),
                                      listConfig: sampleListConfig,
                                      docConfig: MaterializeDocConfig(title: "Doc", relativePath: nil, isPublic: nil,
                                                                      listStyle: nil, rowDataStyle: nil))
        XCTAssertNil(try body()["listConfig"])
    }

    func test_materialize_omitsDocConfigForListOnlyTarget() async throws {
        session.stub(json: createdJSON, statusCode: 201)
        _ = try await sut.materialize(target: .list, source: .messages(messageIds: ["m1"]),
                                      listConfig: sampleListConfig,
                                      docConfig: MaterializeDocConfig(title: "Doc", relativePath: nil, isPublic: nil,
                                                                      listStyle: nil, rowDataStyle: nil))
        XCTAssertNil(try body()["docConfig"])
    }

    func test_materialize_docConfigEncodesHyphenatedRowDataStyle() async throws {
        session.stub(json: createdJSON, statusCode: 201)
        _ = try await sut.materialize(
            target: .doc, source: .lists(listIds: ["l1"]),
            docConfig: MaterializeDocConfig(title: "Doc", relativePath: nil, isPublic: true,
                                            listStyle: .numbered, rowDataStyle: .subItems)
        )
        let docConfig = try XCTUnwrap(try body()["docConfig"] as? [String: Any])
        XCTAssertEqual(docConfig["listStyle"] as? String, "numbered")
        XCTAssertEqual(docConfig["rowDataStyle"] as? String, "sub-items")
        XCTAssertEqual(docConfig["isPublic"] as? Bool, true)
        XCTAssertNil(docConfig["relativePath"], "path is left to the server")
    }

    func test_materialize_includeDataFalseIsSent() async throws {
        session.stub(json: createdJSON, statusCode: 201)
        let config = MaterializeListConfig(title: "T", description: nil, isPublic: nil,
                                           fields: sampleFields, includeData: false)
        _ = try await sut.materialize(target: .list, source: .messages(messageIds: ["m1"]), listConfig: config)
        let listConfig = try XCTUnwrap(try body()["listConfig"] as? [String: Any])
        XCTAssertEqual(listConfig["includeData"] as? Bool, false)
    }

    // MARK: - Response

    func test_materialize_decodesBothCreatedRefs() async throws {
        session.stub(json: createdJSON, statusCode: 201)
        let result = try await sut.materialize(target: .both, source: .messages(messageIds: ["m1"]),
                                               listConfig: sampleListConfig,
                                               docConfig: MaterializeDocConfig(title: "d", relativePath: nil,
                                                                               isPublic: nil, listStyle: nil,
                                                                               rowDataStyle: nil))
        XCTAssertEqual(result.list?.id, "l1")
        XCTAssertEqual(result.list?.title, "3 messages")
        XCTAssertEqual(result.document?.id, "d1")
    }

    func test_materialize_decodesListOnlyResponse() async throws {
        session.stub(json: #"{"list":{"id":"l1","title":"Only a list"}}"#, statusCode: 201)
        let result = try await sut.materialize(target: .list, source: .messages(messageIds: ["m1"]),
                                               listConfig: sampleListConfig)
        XCTAssertEqual(result.list?.title, "Only a list")
        XCTAssertNil(result.document)
    }

    // MARK: - Errors

    func test_materialize_403_throwsForbidden() async throws {
        session.stub(json: #"{"error":"Subscribe to create lists and documents."}"#, statusCode: 403)
        do {
            _ = try await sut.materialize(target: .list, source: .messages(messageIds: ["m1"]),
                                          listConfig: sampleListConfig)
            XCTFail("expected a throw")
        } catch APIError.forbidden {
            // expected — callers must map this to neutral copy, never the raw text
        } catch APIError.status(403) {
            // acceptable for a bodyless 403
        }
    }

    func test_materialize_404_throwsStatus() async throws {
        session.stub(json: #"{"error":"Not found"}"#, statusCode: 404)
        do {
            _ = try await sut.materialize(target: .list, source: .messages(messageIds: ["gone"]),
                                          listConfig: sampleListConfig)
            XCTFail("expected a throw")
        } catch {
            // any throw is fine; the point is it doesn't silently succeed
        }
    }
}
