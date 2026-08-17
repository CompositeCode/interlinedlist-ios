import XCTest
@testable import InterlinedList

final class APIClientSearchUsersTests: XCTestCase {
    var sut: APIClient!
    var session: MockURLSession!

    override func setUp() {
        super.setUp()
        session = MockURLSession()
        sut = APIClient(session: session)
        sut.setBearerToken("tok")
    }

    func test_searchUsers_sendsGetToCorrectPath() async throws {
        session.stub(json: #"{"users":[]}"#)
        _ = try await sut.searchUsers(query: "ada")
        XCTAssertEqual(session.lastRequest?.httpMethod, "GET")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/users/search")
    }

    func test_searchUsers_sendsQueryAndDefaultLimit() async throws {
        session.stub(json: #"{"users":[]}"#)
        _ = try await sut.searchUsers(query: "ada")
        let items = URLComponents(url: session.lastRequest!.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(items.first { $0.name == "q" }?.value, "ada")
        XCTAssertEqual(items.first { $0.name == "limit" }?.value, "20")
    }

    func test_searchUsers_customLimit() async throws {
        session.stub(json: #"{"users":[]}"#)
        _ = try await sut.searchUsers(query: "bob", limit: 5)
        let items = URLComponents(url: session.lastRequest!.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(items.first { $0.name == "limit" }?.value, "5")
    }

    func test_searchUsers_percentEncodesQuery() async throws {
        session.stub(json: #"{"users":[]}"#)
        _ = try await sut.searchUsers(query: "a b&c")
        let raw = session.lastRequest?.url?.absoluteString ?? ""
        XCTAssertTrue(raw.contains("q=a%20b%26c"), "query not percent-encoded: \(raw)")
        // The encoded ampersand must not introduce a spurious query parameter.
        let items = URLComponents(url: session.lastRequest!.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(items.first { $0.name == "q" }?.value, "a b&c")
    }

    func test_searchUsers_decodesUsers() async throws {
        session.stub(json: #"""
        {"users":[
          {"id":"u1","username":"ada","displayName":"Ada L.","avatar":"https://x/a.png"},
          {"id":"u2","username":"bob","displayName":null,"avatar":null}
        ],"total":2}
        """#)
        let users = try await sut.searchUsers(query: "a")
        XCTAssertEqual(users.count, 2)
        XCTAssertEqual(users.first?.id, "u1")
        XCTAssertEqual(users.first?.username, "ada")
        XCTAssertEqual(users.first?.displayName, "Ada L.")
        XCTAssertEqual(users.first?.avatar, "https://x/a.png")
        XCTAssertEqual(users.last?.displayNameOrUsername, "bob")
    }

    func test_searchUsers_sendsBearerToken() async throws {
        session.stub(json: #"{"users":[]}"#)
        _ = try await sut.searchUsers(query: "ada")
        XCTAssertEqual(session.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
    }

    func test_searchUsers_401_throwsStatusError() async throws {
        session.stub(data: Data(), statusCode: 401)
        do {
            _ = try await sut.searchUsers(query: "ada")
            XCTFail("Expected throw")
        } catch APIError.status(let code) {
            XCTAssertEqual(code, 401)
        }
    }

    func test_searchUsers_400_missingQuery_throwsServerError() async throws {
        session.stub(json: #"{"error":"missing_query"}"#, statusCode: 400)
        do {
            _ = try await sut.searchUsers(query: "x")
            XCTFail("Expected throw")
        } catch APIError.server(let msg) {
            XCTAssertEqual(msg, "missing_query")
        }
    }
}
