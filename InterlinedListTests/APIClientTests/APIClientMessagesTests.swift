import XCTest
@testable import InterlinedList

final class APIClientMessagesTests: XCTestCase {
    var sut: APIClient!
    var session: MockURLSession!

    private let messageJSON = #"{"id":"m1","content":"Hello","user_id":"u1","created_at":"2024-01-01T00:00:00Z"}"#
    private var messagesListJSON: String {
        #"{"messages":[\#(messageJSON)],"pagination":{"total":1,"limit":50,"offset":0,"has_more":false}}"#
    }

    override func setUp() {
        super.setUp()
        session = MockURLSession()
        sut = APIClient(session: session)
        sut.setBearerToken("tok")
    }

    // MARK: messages()

    func test_messages_sendsGetWithBearerToken() async throws {
        session.stub(json: messagesListJSON)
        _ = try await sut.messages()
        XCTAssertEqual(session.lastRequest?.httpMethod, "GET")
        XCTAssertEqual(session.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
    }

    func test_messages_pathContainsLimitAndOffset() async throws {
        session.stub(json: messagesListJSON)
        _ = try await sut.messages(limit: 10, offset: 20)
        let url = session.lastRequest?.url?.absoluteString ?? ""
        XCTAssertTrue(url.contains("limit=10"))
        XCTAssertTrue(url.contains("offset=20"))
    }

    func test_messages_onlyMine_appendsQueryParam() async throws {
        session.stub(json: messagesListJSON)
        _ = try await sut.messages(onlyMine: true)
        let url = session.lastRequest?.url?.absoluteString ?? ""
        XCTAssertTrue(url.contains("onlyMine=true"))
    }

    func test_messages_tag_appendsQueryParam() async throws {
        session.stub(json: messagesListJSON)
        _ = try await sut.messages(tag: "swift")
        let url = session.lastRequest?.url?.absoluteString ?? ""
        XCTAssertTrue(url.contains("tag=swift"))
    }

    func test_messages_decodesMessages() async throws {
        session.stub(json: messagesListJSON)
        let (msgs, _) = try await sut.messages()
        XCTAssertEqual(msgs.count, 1)
        XCTAssertEqual(msgs.first?.id, "m1")
    }

    func test_messages_decodesPagination() async throws {
        session.stub(json: messagesListJSON)
        let (_, pagination) = try await sut.messages()
        XCTAssertEqual(pagination?.total, 1)
        XCTAssertEqual(pagination?.hasMore, false)
    }

    func test_messages_401_throwsStatusError() async throws {
        session.stub(data: Data(), statusCode: 401)
        do {
            _ = try await sut.messages()
            XCTFail("Expected throw")
        } catch APIError.status(let code) {
            XCTAssertEqual(code, 401)
        }
    }

    // MARK: postMessage()

    func test_postMessage_sendsPost() async throws {
        let wrapped = #"{"data":\#(messageJSON)}"#
        session.stub(json: wrapped)
        _ = try await sut.postMessage(content: "Hi")
        XCTAssertEqual(session.lastRequest?.httpMethod, "POST")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/messages")
    }

    func test_postMessage_bodyIsCamelCase() async throws {
        let wrapped = #"{"data":\#(messageJSON)}"#
        session.stub(json: wrapped)
        _ = try await sut.postMessage(content: "Hi", publiclyVisible: true)
        let body = try XCTUnwrap(session.lastRequest?.httpBody)
        let json = try XCTUnwrap(try? JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertNotNil(json["publiclyVisible"], "Body must use camelCase key 'publiclyVisible'")
        XCTAssertNil(json["publicly_visible"], "Body must NOT use snake_case key")
    }

    func test_postMessage_401_throwsStatusError() async throws {
        session.stub(data: Data(), statusCode: 401)
        do {
            _ = try await sut.postMessage(content: "Hi")
            XCTFail("Expected throw")
        } catch APIError.status(let code) {
            XCTAssertEqual(code, 401)
        }
    }

    // MARK: editMessage()

    func test_editMessage_sendsPutToCorrectPath() async throws {
        let wrapped = #"{"data":\#(messageJSON)}"#
        session.stub(json: wrapped)
        _ = try await sut.editMessage(id: "m1", content: "Updated", publiclyVisible: nil)
        XCTAssertEqual(session.lastRequest?.httpMethod, "PUT")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/messages/m1")
    }

    // MARK: dig() / undig()

    func test_dig_sendsPostToDigPath() async throws {
        session.stub(json: #"{"digCount":1,"dugByMe":true}"#)
        let resp = try await sut.dig(messageId: "m1")
        XCTAssertEqual(session.lastRequest?.httpMethod, "POST")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/messages/m1/dig")
        XCTAssertEqual(resp.digCount, 1)
        XCTAssertTrue(resp.dugByMe)
    }

    func test_undig_sendsDeleteToDigPath() async throws {
        session.stub(json: #"{"digCount":0,"dugByMe":false}"#)
        let resp = try await sut.undig(messageId: "m1")
        XCTAssertEqual(session.lastRequest?.httpMethod, "DELETE")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/messages/m1/dig")
        XCTAssertEqual(resp.digCount, 0)
    }

    // MARK: replies()

    func test_replies_sendsGetToRepliesPath() async throws {
        session.stub(json: #"{"messages":[]}"#)
        _ = try await sut.replies(messageId: "m1")
        XCTAssertTrue(session.lastRequest?.url?.path.contains("/api/messages/m1/replies") == true)
    }

    // MARK: scheduledMessages()

    func test_scheduledMessages_sendsGetToScheduledPath() async throws {
        session.stub(json: #"{"messages":[]}"#)
        _ = try await sut.scheduledMessages()
        XCTAssertTrue(session.lastRequest?.url?.path.contains("/api/messages/scheduled") == true)
    }

    // MARK: deleteMessage()

    func test_deleteMessage_sendsDeleteToCorrectPath() async throws {
        session.stub(data: Data(), statusCode: 204)
        try await sut.deleteMessage(id: "m1")
        XCTAssertEqual(session.lastRequest?.httpMethod, "DELETE")
        XCTAssertTrue(session.lastRequest?.url?.path.hasSuffix("/api/messages/m1") == true)
    }

    func test_deleteMessage_403_throwsServerError() async throws {
        session.stub(data: Data(), statusCode: 403)
        do {
            try await sut.deleteMessage(id: "m1")
            XCTFail("Expected throw")
        } catch APIError.server(let msg) {
            XCTAssertTrue(msg.lowercased().contains("own"))
        }
    }
}
