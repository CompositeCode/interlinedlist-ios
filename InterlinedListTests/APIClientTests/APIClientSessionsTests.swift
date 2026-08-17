import XCTest
@testable import InterlinedList

final class APIClientSessionsTests: XCTestCase {
    var sut: APIClient!
    var session: MockURLSession!

    override func setUp() {
        super.setUp()
        session = MockURLSession()
        sut = APIClient(session: session)
        sut.setBearerToken("tok")
    }

    // MARK: userSessions()

    func test_userSessions_sendsGetToCorrectPath() async throws {
        session.stub(json: #"{"sessions":[]}"#)
        _ = try await sut.userSessions()
        XCTAssertEqual(session.lastRequest?.httpMethod, "GET")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/user/sessions")
    }

    func test_userSessions_sendsBearerToken() async throws {
        session.stub(json: #"{"sessions":[]}"#)
        _ = try await sut.userSessions()
        XCTAssertEqual(session.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
    }

    func test_userSessions_decodesArray() async throws {
        session.stub(json: #"""
        {"sessions":[
          {"id":"s1","deviceLabel":"iPhone 16","createdAt":"2026-07-01T10:00:00.000Z","lastUsedAt":"2026-07-31T09:00:00.000Z","isCurrent":true},
          {"id":"s2","deviceLabel":"MacBook Pro","createdAt":"2026-06-01T10:00:00Z","lastUsedAt":"2026-07-20T09:00:00Z","isCurrent":false}
        ]}
        """#)
        let sessions = try await sut.userSessions()
        XCTAssertEqual(sessions.count, 2)
        XCTAssertEqual(sessions.first?.id, "s1")
        XCTAssertEqual(sessions.first?.deviceLabel, "iPhone 16")
        XCTAssertEqual(sessions.first?.isCurrent, true)
        XCTAssertEqual(sessions.last?.id, "s2")
        XCTAssertEqual(sessions.last?.isCurrent, false)
    }

    func test_userSessions_missingDeviceLabelAndIsCurrent_defaultsDefensively() async throws {
        session.stub(json: #"{"sessions":[{"id":"s3"}]}"#)
        let sessions = try await sut.userSessions()
        XCTAssertEqual(sessions.count, 1)
        XCTAssertNil(sessions.first?.deviceLabel)
        XCTAssertNil(sessions.first?.createdAt)
        XCTAssertNil(sessions.first?.lastUsedAt)
        XCTAssertEqual(sessions.first?.isCurrent, false)
    }

    func test_userSessions_401_throwsStatusError() async throws {
        session.stub(data: Data(), statusCode: 401)
        do {
            _ = try await sut.userSessions()
            XCTFail("Expected throw")
        } catch APIError.status(let code) {
            XCTAssertEqual(code, 401)
        }
    }

    // MARK: revokeSession()

    func test_revokeSession_sendsDeleteToCorrectPath() async throws {
        session.stub(data: Data(), statusCode: 200)
        try await sut.revokeSession(id: "s2")
        XCTAssertEqual(session.lastRequest?.httpMethod, "DELETE")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/user/sessions/s2")
    }

    func test_revokeSession_sendsBearerToken() async throws {
        session.stub(data: Data(), statusCode: 200)
        try await sut.revokeSession(id: "s2")
        XCTAssertEqual(session.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
    }

    func test_revokeSession_toleratesEmptyBody() async throws {
        session.stub(data: Data(), statusCode: 200)
        try await sut.revokeSession(id: "s2")
    }

    func test_revokeSession_401_throwsStatusError() async throws {
        session.stub(data: Data(), statusCode: 401)
        do {
            try await sut.revokeSession(id: "s2")
            XCTFail("Expected throw")
        } catch APIError.status(let code) {
            XCTAssertEqual(code, 401)
        }
    }
}
