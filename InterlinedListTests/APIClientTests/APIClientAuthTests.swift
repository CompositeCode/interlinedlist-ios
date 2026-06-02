import XCTest
@testable import InterlinedList

final class APIClientAuthTests: XCTestCase {
    var sut: APIClient!
    var session: MockURLSession!

    override func setUp() {
        super.setUp()
        session = MockURLSession()
        sut = APIClient(session: session)
    }

    func test_login_sendsCorrectPath() async throws {
        session.stub(json: #"{"token":"abc123"}"#)
        let token = try await sut.login(email: "a@b.com", password: "pass")
        XCTAssertEqual(token, "abc123")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/auth/sync-token")
        XCTAssertEqual(session.lastRequest?.httpMethod, "POST")
        XCTAssertNil(session.lastRequest?.value(forHTTPHeaderField: "Authorization"),
                     "Login must not send a Bearer token")
    }

    func test_login_401_throwsStatusError() async throws {
        session.stub(json: #"{"error":"bad credentials"}"#, statusCode: 401)
        do {
            _ = try await sut.login(email: "a@b.com", password: "wrong")
            XCTFail("Expected APIError.status(401)")
        } catch APIError.status(let code) {
            XCTAssertEqual(code, 401)
        }
    }

    func test_currentUser_sendsBearerToken() async throws {
        sut.setBearerToken("tok")
        session.stub(json: #"{"user":{"id":"1","email":"a@b.com","username":"alice"}}"#)
        _ = try await sut.currentUser()
        XCTAssertEqual(session.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
    }
}
