import XCTest
@testable import InterlinedList

final class APIClientPasswordResetTests: XCTestCase {
    var sut: APIClient!
    var session: MockURLSession!

    override func setUp() {
        super.setUp()
        session = MockURLSession()
        sut = APIClient(session: session)
    }

    // MARK: forgotPassword

    func test_forgotPassword_sendsCorrectPath() async throws {
        session.stub(json: #"{"message":"ok"}"#)
        try await sut.forgotPassword(email: "a@b.com")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/auth/forgot-password")
        XCTAssertEqual(session.lastRequest?.httpMethod, "POST")
    }

    func test_forgotPassword_doesNotSendBearerToken() async throws {
        sut.setBearerToken("tok")
        session.stub(json: #"{"message":"ok"}"#)
        try await sut.forgotPassword(email: "a@b.com")
        XCTAssertNil(session.lastRequest?.value(forHTTPHeaderField: "Authorization"))
    }

    func test_forgotPassword_bodyContainsEmail() async throws {
        session.stub(json: #"{"message":"ok"}"#)
        try await sut.forgotPassword(email: "a@b.com")
        let body = String(data: session.lastRequest?.httpBody ?? Data(), encoding: .utf8) ?? ""
        XCTAssertTrue(body.contains("\"email\":\"a@b.com\""))
    }

    func test_forgotPassword_serverErrorPropagates() async throws {
        session.stub(json: #"{"error":"rate limited"}"#, statusCode: 500)
        do {
            try await sut.forgotPassword(email: "a@b.com")
            XCTFail("Expected throw")
        } catch APIError.server(let message) {
            XCTAssertEqual(message, "rate limited")
        }
    }

    // MARK: resetPassword

    func test_resetPassword_sendsCorrectPath() async throws {
        session.stub(json: #"{"message":"ok"}"#)
        try await sut.resetPassword(token: "tok123", password: "newPass!")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/auth/reset-password")
        XCTAssertEqual(session.lastRequest?.httpMethod, "POST")
    }

    func test_resetPassword_bodyContainsTokenAndPassword() async throws {
        session.stub(json: #"{"message":"ok"}"#)
        try await sut.resetPassword(token: "tok123", password: "newPass!")
        let body = String(data: session.lastRequest?.httpBody ?? Data(), encoding: .utf8) ?? ""
        XCTAssertTrue(body.contains("\"token\":\"tok123\""))
        XCTAssertTrue(body.contains("\"password\":\"newPass!\""))
    }

    func test_resetPassword_doesNotSendBearerToken() async throws {
        sut.setBearerToken("tok")
        session.stub(json: #"{"message":"ok"}"#)
        try await sut.resetPassword(token: "abc", password: "pw")
        XCTAssertNil(session.lastRequest?.value(forHTTPHeaderField: "Authorization"))
    }

    func test_resetPassword_400_throwsStatusError() async throws {
        session.stub(data: Data(), statusCode: 400)
        do {
            try await sut.resetPassword(token: "bad", password: "pw")
            XCTFail("Expected throw")
        } catch APIError.status(let code) {
            XCTAssertEqual(code, 400)
        }
    }
}
