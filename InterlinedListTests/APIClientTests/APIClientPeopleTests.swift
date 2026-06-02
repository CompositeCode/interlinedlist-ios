import XCTest
@testable import InterlinedList

final class APIClientPeopleTests: XCTestCase {
    var sut: APIClient!
    var session: MockURLSession!

    private let messageJSON = #"{"id":"m1","content":"Hi","user_id":"u1","created_at":"2024-01-01T00:00:00Z"}"#
    private let listJSON = #"{"id":"l1","title":"List","created_at":"2024-01-01T00:00:00Z"}"#

    override func setUp() {
        super.setUp()
        session = MockURLSession()
        sut = APIClient(session: session)
        sut.setBearerToken("tok")
    }

    // MARK: publicMessages()

    func test_publicMessages_sendsGetToCorrectPath() async throws {
        session.stub(json: #"{"messages":[\#(messageJSON)]}"#)
        _ = try await sut.publicMessages(username: "alice")
        XCTAssertEqual(session.lastRequest?.httpMethod, "GET")
        XCTAssertTrue(session.lastRequest?.url?.path.contains("/api/user/alice/messages") == true)
    }

    func test_publicMessages_includesLimitAndOffset() async throws {
        session.stub(json: #"{"messages":[]}"#)
        _ = try await sut.publicMessages(username: "alice", limit: 10, offset: 5)
        let url = session.lastRequest?.url?.absoluteString ?? ""
        XCTAssertTrue(url.contains("limit=10"))
        XCTAssertTrue(url.contains("offset=5"))
    }

    func test_publicMessages_decodesMessages() async throws {
        session.stub(json: #"{"messages":[\#(messageJSON)]}"#)
        let (msgs, _) = try await sut.publicMessages(username: "alice")
        XCTAssertEqual(msgs.count, 1)
        XCTAssertEqual(msgs.first?.id, "m1")
    }

    func test_publicMessages_401_throws() async throws {
        session.stub(data: Data(), statusCode: 401)
        do {
            _ = try await sut.publicMessages(username: "alice")
            XCTFail("Expected throw")
        } catch APIError.status(let code) {
            XCTAssertEqual(code, 401)
        }
    }

    // MARK: publicLists()

    func test_publicLists_sendsGetToCorrectPath() async throws {
        session.stub(json: #"{"lists":[\#(listJSON)]}"#)
        let lists = try await sut.publicLists(username: "alice")
        XCTAssertEqual(session.lastRequest?.httpMethod, "GET")
        XCTAssertTrue(session.lastRequest?.url?.path.contains("/api/users/alice/lists") == true)
        XCTAssertEqual(lists.count, 1)
    }

    func test_publicLists_usersPathNotUserPath() async throws {
        // /api/users/[username]/lists (plural "users") vs /api/user/[username]/messages (singular)
        session.stub(json: #"{"lists":[]}"#)
        _ = try await sut.publicLists(username: "bob")
        let path = session.lastRequest?.url?.path ?? ""
        XCTAssertTrue(path.contains("/api/users/bob/lists"))
        XCTAssertFalse(path.contains("/api/user/bob/lists"))
    }

    func test_publicLists_encodesSpecialCharacters() async throws {
        session.stub(json: #"{"lists":[]}"#)
        _ = try await sut.publicLists(username: "user name")
        let path = session.lastRequest?.url?.path ?? ""
        XCTAssertFalse(path.contains(" "), "Username with spaces must be percent-encoded")
    }
}
