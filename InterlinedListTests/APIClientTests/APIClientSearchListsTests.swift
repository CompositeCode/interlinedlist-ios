import XCTest
@testable import InterlinedList

final class APIClientSearchListsTests: XCTestCase {
    var sut: APIClient!
    var session: MockURLSession!

    private let listJSON = #"{"id":"l1","title":"Books to Read","description":"Personal queue","is_public":false,"item_count":12,"created_at":"2026-01-01T00:00:00Z"}"#

    override func setUp() {
        super.setUp()
        session = MockURLSession()
        sut = APIClient(session: session)
        sut.setBearerToken("tok")
    }

    // MARK: searchLists()

    func test_searchLists_sendsGetToCorrectPath() async throws {
        session.stub(json: #"{"lists":[],"pagination":null}"#)
        _ = try await sut.searchLists(q: "books")
        XCTAssertEqual(session.lastRequest?.httpMethod, "GET")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/lists/search")
    }

    func test_searchLists_sendsBearerToken() async throws {
        session.stub(json: #"{"lists":[],"pagination":null}"#)
        _ = try await sut.searchLists(q: "q")
        XCTAssertEqual(session.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
    }

    func test_searchLists_includesQueryParam() async throws {
        session.stub(json: #"{"lists":[],"pagination":null}"#)
        _ = try await sut.searchLists(q: "books")
        let url = session.lastRequest?.url?.absoluteString ?? ""
        XCTAssertTrue(url.contains("q=books"), "Expected q=books in \(url)")
    }

    func test_searchLists_includesLimitAndOffset() async throws {
        session.stub(json: #"{"lists":[],"pagination":null}"#)
        _ = try await sut.searchLists(q: "x", limit: 10, offset: 5)
        let url = session.lastRequest?.url?.absoluteString ?? ""
        XCTAssertTrue(url.contains("limit=10"), "Expected limit=10 in \(url)")
        XCTAssertTrue(url.contains("offset=5"), "Expected offset=5 in \(url)")
    }

    func test_searchLists_decodesResults() async throws {
        session.stub(json: #"{"lists":[\#(listJSON)],"pagination":null}"#)
        let (lists, _) = try await sut.searchLists(q: "books")
        XCTAssertEqual(lists.count, 1)
        XCTAssertEqual(lists.first?.id, "l1")
        XCTAssertEqual(lists.first?.name, "Books to Read")
        XCTAssertEqual(lists.first?.description, "Personal queue")
        XCTAssertEqual(lists.first?.isPublic, false)
        XCTAssertEqual(lists.first?.itemCount, 12)
    }

    func test_searchLists_decodesPagination() async throws {
        session.stub(json: #"{"lists":[],"pagination":{"total":42,"limit":20,"offset":0,"hasMore":true}}"#)
        let (_, pagination) = try await sut.searchLists(q: "q")
        XCTAssertEqual(pagination?.total, 42)
        XCTAssertEqual(pagination?.limit, 20)
        XCTAssertEqual(pagination?.offset, 0)
        XCTAssertEqual(pagination?.hasMore, true)
    }

    func test_searchLists_nullPagination_returnsNil() async throws {
        session.stub(json: #"{"lists":[],"pagination":null}"#)
        let (_, pagination) = try await sut.searchLists(q: "q")
        XCTAssertNil(pagination)
    }

    func test_searchLists_nullDescription_handled() async throws {
        let nullDescJSON = #"{"id":"l2","title":"Untitled","description":null,"is_public":true,"item_count":0,"created_at":"2026-01-01T00:00:00Z"}"#
        session.stub(json: #"{"lists":[\#(nullDescJSON)],"pagination":null}"#)
        let (lists, _) = try await sut.searchLists(q: "q")
        XCTAssertEqual(lists.count, 1)
        XCTAssertNil(lists.first?.description)
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

    func test_searchLists_serverError_throwsServerError() async throws {
        session.stub(json: #"{"error":"search unavailable"}"#, statusCode: 503)
        do {
            _ = try await sut.searchLists(q: "q")
            XCTFail("Expected throw")
        } catch APIError.server(let msg) {
            XCTAssertEqual(msg, "search unavailable")
        }
    }

    func test_searchLists_percentEncodesQuery() async throws {
        session.stub(json: #"{"lists":[],"pagination":null}"#)
        _ = try await sut.searchLists(q: "hello world")
        let url = session.lastRequest?.url?.absoluteString ?? ""
        XCTAssertTrue(url.contains("hello"), "Expected 'hello' in encoded URL: \(url)")
    }
}
