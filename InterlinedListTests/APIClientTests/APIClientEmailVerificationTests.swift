import XCTest
@testable import InterlinedList

final class APIClientEmailVerificationTests: XCTestCase {
    var sut: APIClient!
    var session: MockURLSession!

    override func setUp() {
        super.setUp()
        session = MockURLSession()
        sut = APIClient(session: session)
        sut.setBearerToken("tok")
    }

    // MARK: sendVerificationEmail

    func test_sendVerificationEmail_sendsCorrectPath() async throws {
        session.stub(json: #"{"message":"sent"}"#)
        try await sut.sendVerificationEmail()
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/auth/send-verification-email")
        XCTAssertEqual(session.lastRequest?.httpMethod, "POST")
    }

    func test_sendVerificationEmail_sendsBearerToken() async throws {
        session.stub(json: #"{"message":"sent"}"#)
        try await sut.sendVerificationEmail()
        XCTAssertEqual(session.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
    }

    func test_sendVerificationEmail_401_throws() async throws {
        session.stub(data: Data(), statusCode: 401)
        do {
            try await sut.sendVerificationEmail()
            XCTFail("Expected throw")
        } catch APIError.status(let code) {
            XCTAssertEqual(code, 401)
        }
    }

    func test_sendVerificationEmail_500_throws() async throws {
        session.stub(data: Data(), statusCode: 500)
        do {
            try await sut.sendVerificationEmail()
            XCTFail("Expected throw")
        } catch APIError.status(let code) {
            XCTAssertEqual(code, 500)
        }
    }

    // MARK: verifyEmail

    func test_verifyEmail_sendsCorrectPath() async throws {
        session.stub(json: #"{"message":"verified"}"#)
        try await sut.verifyEmail(token: "v-token")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/auth/verify-email")
        XCTAssertEqual(session.lastRequest?.httpMethod, "POST")
    }

    func test_verifyEmail_bodyContainsToken() async throws {
        session.stub(json: #"{"message":"verified"}"#)
        try await sut.verifyEmail(token: "v-token")
        let body = String(data: session.lastRequest?.httpBody ?? Data(), encoding: .utf8) ?? ""
        XCTAssertTrue(body.contains("\"token\":\"v-token\""))
    }

    func test_verifyEmail_doesNotSendBearerToken() async throws {
        // verifyEmail is a verification step — works without an existing session.
        session.stub(json: #"{"message":"verified"}"#)
        try await sut.verifyEmail(token: "v-token")
        XCTAssertNil(session.lastRequest?.value(forHTTPHeaderField: "Authorization"))
    }

    // MARK: verifyEmailChange

    func test_verifyEmailChange_sendsCorrectPath() async throws {
        session.stub(json: #"{"message":"ok"}"#)
        try await sut.verifyEmailChange(token: "c-token")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/auth/verify-email-change")
        XCTAssertEqual(session.lastRequest?.httpMethod, "POST")
    }

    func test_verifyEmailChange_bodyContainsToken() async throws {
        session.stub(json: #"{"message":"ok"}"#)
        try await sut.verifyEmailChange(token: "c-token")
        let body = String(data: session.lastRequest?.httpBody ?? Data(), encoding: .utf8) ?? ""
        XCTAssertTrue(body.contains("\"token\":\"c-token\""))
    }

    // MARK: requestEmailChange

    func test_requestEmailChange_sendsCorrectPath() async throws {
        session.stub(json: #"{"message":"check inbox"}"#)
        try await sut.requestEmailChange(newEmail: "new@example.com", password: "pw")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/user/change-email/request")
        XCTAssertEqual(session.lastRequest?.httpMethod, "POST")
    }

    func test_requestEmailChange_bodyUsesCamelCase() async throws {
        session.stub(json: #"{"message":"check inbox"}"#)
        try await sut.requestEmailChange(newEmail: "new@example.com", password: "pw")
        let body = String(data: session.lastRequest?.httpBody ?? Data(), encoding: .utf8) ?? ""
        XCTAssertTrue(body.contains("\"newEmail\":\"new@example.com\""),
                      "Body should use camelCase 'newEmail'. Got: \(body)")
        XCTAssertFalse(body.contains("new_email"),
                       "Body must not snake_case 'newEmail'. Got: \(body)")
    }

    func test_requestEmailChange_sendsBearerToken() async throws {
        session.stub(json: #"{"message":"ok"}"#)
        try await sut.requestEmailChange(newEmail: "new@e.com", password: "pw")
        XCTAssertEqual(session.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
    }

    func test_requestEmailChange_401_throws() async throws {
        session.stub(data: Data(), statusCode: 401)
        do {
            try await sut.requestEmailChange(newEmail: "new@e.com", password: "bad")
            XCTFail("Expected throw")
        } catch APIError.status(let code) {
            XCTAssertEqual(code, 401)
        }
    }
}
