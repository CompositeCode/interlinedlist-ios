import XCTest
@testable import InterlinedList

final class APIClientSearchDocumentsTests: XCTestCase {
    var sut: APIClient!
    var session: MockURLSession!

    private let docJSON = #"{"id":"d1","title":"Meeting Notes"}"#

    override func setUp() {
        super.setUp()
        session = MockURLSession()
        sut = APIClient(session: session)
        sut.setBearerToken("tok")
    }

    // MARK: searchDocuments()

    func test_searchDocuments_sendsGetToCorrectPath() async throws {
        session.stub(json: #"{"documents":[],"pagination":null}"#)
        _ = try await sut.searchDocuments(q: "notes")
        XCTAssertEqual(session.lastRequest?.httpMethod, "GET")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/documents/search")
    }

    func test_searchDocuments_sendsBearerToken() async throws {
        session.stub(json: #"{"documents":[],"pagination":null}"#)
        _ = try await sut.searchDocuments(q: "q")
        XCTAssertEqual(session.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
    }

    func test_searchDocuments_includesQueryParam() async throws {
        session.stub(json: #"{"documents":[],"pagination":null}"#)
        _ = try await sut.searchDocuments(q: "notes")
        let url = session.lastRequest?.url?.absoluteString ?? ""
        XCTAssertTrue(url.contains("q=notes"), "Expected q=notes in \(url)")
    }

    func test_searchDocuments_includesLimitAndOffset() async throws {
        session.stub(json: #"{"documents":[],"pagination":null}"#)
        _ = try await sut.searchDocuments(q: "x", limit: 10, offset: 5)
        let url = session.lastRequest?.url?.absoluteString ?? ""
        XCTAssertTrue(url.contains("limit=10"), "Expected limit=10 in \(url)")
        XCTAssertTrue(url.contains("offset=5"), "Expected offset=5 in \(url)")
    }

    func test_searchDocuments_decodesResults() async throws {
        session.stub(json: #"{"documents":[\#(docJSON)],"pagination":null}"#)
        let (docs, _) = try await sut.searchDocuments(q: "meeting")
        XCTAssertEqual(docs.count, 1)
        XCTAssertEqual(docs.first?.id, "d1")
        XCTAssertEqual(docs.first?.title, "Meeting Notes")
    }

    func test_searchDocuments_decodesPagination() async throws {
        session.stub(json: #"{"documents":[],"pagination":{"total":100,"limit":20,"offset":0,"hasMore":true}}"#)
        let (_, pagination) = try await sut.searchDocuments(q: "q")
        XCTAssertEqual(pagination?.total, 100)
        XCTAssertEqual(pagination?.limit, 20)
        XCTAssertEqual(pagination?.hasMore, true)
    }

    func test_searchDocuments_nullPagination_returnsNil() async throws {
        session.stub(json: #"{"documents":[],"pagination":null}"#)
        let (_, pagination) = try await sut.searchDocuments(q: "q")
        XCTAssertNil(pagination)
    }

    func test_searchDocuments_401_throwsStatusError() async throws {
        session.stub(data: Data(), statusCode: 401)
        do {
            _ = try await sut.searchDocuments(q: "q")
            XCTFail("Expected throw")
        } catch APIError.status(let code) {
            XCTAssertEqual(code, 401)
        }
    }

    func test_searchDocuments_serverError_throwsServerError() async throws {
        session.stub(json: #"{"error":"search unavailable"}"#, statusCode: 503)
        do {
            _ = try await sut.searchDocuments(q: "q")
            XCTFail("Expected throw")
        } catch APIError.server(let msg) {
            XCTAssertEqual(msg, "search unavailable")
        }
    }

    func test_searchDocuments_percentEncodesQuery() async throws {
        session.stub(json: #"{"documents":[],"pagination":null}"#)
        _ = try await sut.searchDocuments(q: "hello world")
        let url = session.lastRequest?.url?.absoluteString ?? ""
        XCTAssertTrue(url.contains("hello"), "Expected 'hello' in encoded URL: \(url)")
    }

    // MARK: updateDocument(folderId:)

    func test_updateDocument_withFolderId_sendsFolderIdInBody() async throws {
        let docJSON = #"{"id":"d1","title":"Doc"}"#
        session.stub(json: #"{"document":\#(docJSON)}"#)
        _ = try await sut.updateDocument(id: "d1", title: "Doc", content: nil, isPublic: false, folderId: "f1")
        let body = try XCTUnwrap(session.lastRequest?.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["folder_id"] as? String, "f1")
    }

    func test_updateDocument_nilFolderId_omitsFolderIdFromBody() async throws {
        let docJSON = #"{"id":"d1","title":"Doc"}"#
        session.stub(json: #"{"document":\#(docJSON)}"#)
        _ = try await sut.updateDocument(id: "d1", title: "Doc", content: nil, isPublic: false, folderId: nil)
        let body = try XCTUnwrap(session.lastRequest?.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertNil(json["folder_id"], "folderId should be absent when nil is passed")
    }

    func test_updateDocument_emptyFolderId_sendsEmptyString() async throws {
        let docJSON = #"{"id":"d1","title":"Doc"}"#
        session.stub(json: #"{"document":\#(docJSON)}"#)
        _ = try await sut.updateDocument(id: "d1", title: "Doc", content: nil, isPublic: false, folderId: "")
        let body = try XCTUnwrap(session.lastRequest?.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["folder_id"] as? String, "")
    }

    func test_updateDocument_withFolderId_usesPatchMethod() async throws {
        let docJSON = #"{"id":"d1","title":"Doc"}"#
        session.stub(json: #"{"document":\#(docJSON)}"#)
        _ = try await sut.updateDocument(id: "d1", title: "Doc", content: nil, isPublic: false, folderId: "f1")
        XCTAssertEqual(session.lastRequest?.httpMethod, "PATCH")
    }

    func test_updateDocument_defaultFolderIdIsNil_backwardsCompatible() async throws {
        let docJSON = #"{"id":"d1","title":"Doc"}"#
        session.stub(json: #"{"document":\#(docJSON)}"#)
        _ = try await sut.updateDocument(id: "d1", title: "Doc", content: nil, isPublic: false)
        let body = try XCTUnwrap(session.lastRequest?.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertNil(json["folder_id"])
    }
}
