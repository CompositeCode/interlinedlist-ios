import XCTest
@testable import InterlinedList

final class APIClientTagsTests: XCTestCase {
    var sut: APIClient!
    var session: MockURLSession!

    override func setUp() {
        super.setUp()
        session = MockURLSession()
        sut = APIClient(session: session)
        sut.setBearerToken("tok")
    }

    // MARK: - trendingTags

    func test_trendingTags_sendsGetToCorrectPath() async throws {
        session.stub(json: #"{"tags":[]}"#)
        _ = try await sut.trendingTags()
        XCTAssertEqual(session.lastRequest?.httpMethod, "GET")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/tags/trending")
    }

    func test_trendingTags_sendsDefaultWindowAndLimit() async throws {
        session.stub(json: #"{"tags":[]}"#)
        _ = try await sut.trendingTags()
        let items = URLComponents(url: session.lastRequest!.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(items.first { $0.name == "window" }?.value, "week")
        XCTAssertEqual(items.first { $0.name == "limit" }?.value, "20")
    }

    func test_trendingTags_customWindowAndLimit() async throws {
        session.stub(json: #"{"tags":[]}"#)
        _ = try await sut.trendingTags(window: "month", limit: 50)
        let items = URLComponents(url: session.lastRequest!.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(items.first { $0.name == "window" }?.value, "month")
        XCTAssertEqual(items.first { $0.name == "limit" }?.value, "50")
    }

    func test_trendingTags_decodesTags() async throws {
        session.stub(json: #"""
        {"tags":[
          {"tag":"interlinedlist","count":13,"lastUsedAt":"2026-08-13T05:24:06.402Z"},
          {"tag":"llms","count":3,"lastUsedAt":"2026-08-13T16:00:19.383Z"}
        ]}
        """#)
        let tags = try await sut.trendingTags()
        XCTAssertEqual(tags.count, 2)
        XCTAssertEqual(tags.first?.tag, "interlinedlist")
        XCTAssertEqual(tags.first?.count, 13)
        XCTAssertEqual(tags.first?.lastUsedAt, "2026-08-13T05:24:06.402Z")
        XCTAssertEqual(tags.first?.id, "interlinedlist")
    }

    func test_trendingTags_decodesWhenLastUsedAtMissing() async throws {
        session.stub(json: #"{"tags":[{"tag":"ai","count":8}]}"#)
        let tags = try await sut.trendingTags()
        XCTAssertEqual(tags.first?.tag, "ai")
        XCTAssertNil(tags.first?.lastUsedAt)
    }

    func test_trendingTags_sendsBearerToken() async throws {
        session.stub(json: #"{"tags":[]}"#)
        _ = try await sut.trendingTags()
        XCTAssertEqual(session.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
    }

    func test_trendingTags_401_throwsStatusError() async throws {
        session.stub(data: Data(), statusCode: 401)
        do {
            _ = try await sut.trendingTags()
            XCTFail("Expected throw")
        } catch APIError.status(let code) {
            XCTAssertEqual(code, 401)
        }
    }

    // MARK: - tagAutocomplete

    func test_tagAutocomplete_sendsGetToCorrectPath() async throws {
        session.stub(json: #"{"tags":[]}"#)
        _ = try await sut.tagAutocomplete(query: "ai")
        XCTAssertEqual(session.lastRequest?.httpMethod, "GET")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/tags/autocomplete")
    }

    func test_tagAutocomplete_sendsQueryAndDefaultLimit() async throws {
        session.stub(json: #"{"tags":[]}"#)
        _ = try await sut.tagAutocomplete(query: "ai")
        let items = URLComponents(url: session.lastRequest!.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(items.first { $0.name == "q" }?.value, "ai")
        XCTAssertEqual(items.first { $0.name == "limit" }?.value, "10")
    }

    func test_tagAutocomplete_percentEncodesQuery() async throws {
        session.stub(json: #"{"tags":[]}"#)
        _ = try await sut.tagAutocomplete(query: "a b&c")
        let items = URLComponents(url: session.lastRequest!.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(items.first { $0.name == "q" }?.value, "a b&c")
    }

    func test_tagAutocomplete_decodesSuggestions() async throws {
        session.stub(json: #"{"tags":[{"tag":"ai","count":8},{"tag":"ai coding","count":2}]}"#)
        let suggestions = try await sut.tagAutocomplete(query: "ai")
        XCTAssertEqual(suggestions.count, 2)
        XCTAssertEqual(suggestions.first?.tag, "ai")
        XCTAssertEqual(suggestions.first?.count, 8)
        XCTAssertEqual(suggestions.last?.tag, "ai coding")
    }

    func test_tagAutocomplete_400_blankQuery_throwsServerError() async throws {
        session.stub(json: #"{"error":"Query parameter 'q' is required"}"#, statusCode: 400)
        do {
            _ = try await sut.tagAutocomplete(query: "x")
            XCTFail("Expected throw")
        } catch APIError.server(let msg) {
            XCTAssertEqual(msg, "Query parameter 'q' is required")
        }
    }
}
