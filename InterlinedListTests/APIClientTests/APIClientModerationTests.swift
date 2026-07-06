import XCTest
@testable import InterlinedList

final class APIClientModerationTests: XCTestCase {
    var sut: APIClient!
    var session: MockURLSession!

    override func setUp() {
        super.setUp()
        session = MockURLSession()
        sut = APIClient(session: session)
        sut.setBearerToken("tok")
    }

    // MARK: reportMessage()

    func test_reportMessage_sendsPostToCorrectPath() async throws {
        session.stub(json: #"{"reported":true}"#)
        try await sut.reportMessage(id: "msg-id", reason: .spam, detail: nil)
        XCTAssertEqual(session.lastRequest?.httpMethod, "POST")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/messages/msg-id/report")
    }

    func test_reportMessage_sendsBearerToken() async throws {
        session.stub(json: #"{"reported":true}"#)
        try await sut.reportMessage(id: "msg-id", reason: .spam, detail: nil)
        XCTAssertEqual(session.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
    }

    func test_reportMessage_bodyContainsReason() async throws {
        session.stub(json: #"{"reported":true}"#)
        try await sut.reportMessage(id: "msg-id", reason: .spam, detail: nil)
        let bodyData = try XCTUnwrap(session.lastRequest?.httpBody)
        let json = try JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
        XCTAssertEqual(json?["reason"] as? String, "spam")
    }

    func test_reportMessage_401_throws() async throws {
        session.stub(data: Data(), statusCode: 401)
        do {
            try await sut.reportMessage(id: "msg-id", reason: .spam, detail: nil)
            XCTFail("Expected throw")
        } catch APIError.status(let code) {
            XCTAssertEqual(code, 401)
        }
    }

    // MARK: reportUser()

    func test_reportUser_sendsPostToCorrectPath() async throws {
        session.stub(json: #"{"reported":true}"#)
        try await sut.reportUser(id: "user-id", reason: .harassment, detail: nil)
        XCTAssertEqual(session.lastRequest?.httpMethod, "POST")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/users/user-id/report")
    }

    // MARK: blockUser()

    func test_blockUser_sendsPostToCorrectPath() async throws {
        session.stub(json: #"{"blocked":true}"#)
        try await sut.blockUser(id: "user-id")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/users/user-id/block")
    }

    func test_blockUser_httpMethodIsPost() async throws {
        session.stub(json: #"{"blocked":true}"#)
        try await sut.blockUser(id: "user-id")
        XCTAssertEqual(session.lastRequest?.httpMethod, "POST")
    }

    // MARK: unblockUser()

    func test_unblockUser_sendsDeleteToCorrectPath() async throws {
        session.stub(data: Data(), statusCode: 200)
        try await sut.unblockUser(id: "user-id")
        XCTAssertEqual(session.lastRequest?.httpMethod, "DELETE")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/users/user-id/block")
    }

    // MARK: blockedUsers()

    func test_blockedUsers_sendsGetRequest() async throws {
        session.stub(json: #"{"blockedUsers":[],"pagination":null}"#)
        _ = try await sut.blockedUsers()
        XCTAssertEqual(session.lastRequest?.httpMethod, "GET")
        XCTAssertTrue(session.lastRequest?.url?.path.hasPrefix("/api/user/blocks") == true)
    }

    func test_blockedUsers_decodesResponse() async throws {
        session.stub(json: #"{"blockedUsers":[{"id":"u1","username":"alice","displayName":null,"avatar":null}],"pagination":null}"#)
        let response = try await sut.blockedUsers()
        XCTAssertEqual(response.blockedUsers.count, 1)
        XCTAssertEqual(response.blockedUsers.first?.id, "u1")
        XCTAssertEqual(response.blockedUsers.first?.username, "alice")
    }

    // MARK: muteUser()

    func test_muteUser_sendsPostToCorrectPath() async throws {
        session.stub(json: #"{"muted":true}"#)
        try await sut.muteUser(id: "user-id")
        XCTAssertEqual(session.lastRequest?.httpMethod, "POST")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/users/user-id/mute")
    }

    // MARK: unmuteUser()

    func test_unmuteUser_sendsDeleteRequest() async throws {
        session.stub(data: Data(), statusCode: 200)
        try await sut.unmuteUser(id: "user-id")
        XCTAssertEqual(session.lastRequest?.httpMethod, "DELETE")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/users/user-id/mute")
    }

    // MARK: mutedUsers()

    func test_mutedUsers_decodesResponse() async throws {
        session.stub(json: #"{"mutedUsers":[{"id":"u2","username":"bob","displayName":null,"avatar":null}],"pagination":null}"#)
        let response = try await sut.mutedUsers()
        XCTAssertEqual(response.mutedUsers.count, 1)
        XCTAssertEqual(response.mutedUsers.first?.id, "u2")
        XCTAssertEqual(response.mutedUsers.first?.username, "bob")
    }
}
