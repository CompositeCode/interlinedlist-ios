import XCTest
@testable import InterlinedList

final class APIClientDirectMessagesTests: XCTestCase {
    var sut: APIClient!
    var session: MockURLSession!

    override func setUp() {
        super.setUp()
        session = MockURLSession()
        sut = APIClient(session: session)
        sut.setBearerToken("tok")
    }

    private let dmMessageJSON = """
    {
      "id": "m1",
      "pairKey": "a:b",
      "senderId": "s1",
      "recipientId": "r1",
      "body": "hello",
      "imageUrls": ["https://img/1.png"],
      "createdAt": "2026-07-31T12:00:00.000Z",
      "readAt": null,
      "sender": {"id":"s1","username":"alice","displayName":"Alice","avatar":null},
      "recipient": {"id":"r1","username":"bob","displayName":null,"avatar":null},
      "preview": "hello there"
    }
    """

    // MARK: directMessages()

    func test_directMessages_buildsFolderAndCursorQuery() async throws {
        session.stub(json: #"{"items":[],"nextCursor":null}"#)
        _ = try await sut.directMessages(folder: .sent, cursor: "cur123")
        XCTAssertEqual(session.lastRequest?.httpMethod, "GET")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/dm")
        let query = session.lastRequest?.url?.query ?? ""
        XCTAssertTrue(query.contains("folder=sent"), "query was \(query)")
        XCTAssertTrue(query.contains("cursor=cur123"), "query was \(query)")
    }

    func test_directMessages_inboxOmitsCursorWhenNil() async throws {
        session.stub(json: #"{"items":[],"nextCursor":null}"#)
        _ = try await sut.directMessages(folder: .inbox)
        let query = session.lastRequest?.url?.query ?? ""
        XCTAssertTrue(query.contains("folder=inbox"))
        XCTAssertFalse(query.contains("cursor"))
    }

    func test_directMessages_decodesItemsAndCursor() async throws {
        session.stub(json: "{\"items\":[\(dmMessageJSON)],\"nextCursor\":\"next\"}")
        let response = try await sut.directMessages(folder: .inbox)
        XCTAssertEqual(response.items.count, 1)
        XCTAssertEqual(response.items.first?.id, "m1")
        XCTAssertEqual(response.items.first?.imageUrls.first, "https://img/1.png")
        XCTAssertEqual(response.nextCursor, "next")
    }

    func test_directMessages_sendsBearerToken() async throws {
        session.stub(json: #"{"items":[],"nextCursor":null}"#)
        _ = try await sut.directMessages(folder: .inbox)
        XCTAssertEqual(session.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
    }

    func test_directMessages_401_throws() async throws {
        session.stub(data: Data(), statusCode: 401)
        do {
            _ = try await sut.directMessages(folder: .inbox)
            XCTFail("Expected throw")
        } catch APIError.status(let code) {
            XCTAssertEqual(code, 401)
        }
    }

    // MARK: sendDirectMessage()

    func test_sendDirectMessage_usesPostToDMPath() async throws {
        session.stub(json: "{\"message\":\(dmMessageJSON)}")
        _ = try await sut.sendDirectMessage(recipientId: "r1", body: "hi")
        XCTAssertEqual(session.lastRequest?.httpMethod, "POST")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/dm")
    }

    func test_sendDirectMessage_bodyUsesCamelCaseKeys() async throws {
        session.stub(json: "{\"message\":\(dmMessageJSON)}")
        _ = try await sut.sendDirectMessage(recipientId: "r1", body: "hi", imageUrls: ["https://img/x.png"])
        let bodyData = try XCTUnwrap(session.lastRequest?.httpBody)
        let json = try JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
        XCTAssertNotNil(json?["recipientId"], "recipientId key must be camelCase")
        XCTAssertNotNil(json?["imageUrls"], "imageUrls key must be camelCase")
        XCTAssertNil(json?["recipient_id"], "must NOT be snake_case")
        XCTAssertNil(json?["image_urls"], "must NOT be snake_case")
        XCTAssertEqual(json?["recipientId"] as? String, "r1")
        XCTAssertEqual(json?["body"] as? String, "hi")
    }

    func test_sendDirectMessage_decodesReturnedMessage() async throws {
        session.stub(json: "{\"message\":\(dmMessageJSON)}")
        let message = try await sut.sendDirectMessage(recipientId: "r1", body: "hello")
        XCTAssertEqual(message.id, "m1")
        XCTAssertEqual(message.senderId, "s1")
        XCTAssertEqual(message.body, "hello")
    }

    func test_sendDirectMessage_notMutual_mapsToServerError() async throws {
        session.stub(json: #"{"error":"not_mutual"}"#, statusCode: 403)
        do {
            _ = try await sut.sendDirectMessage(recipientId: "r1", body: "hi")
            XCTFail("Expected throw")
        } catch APIError.server(let message) {
            XCTAssertEqual(message, "not_mutual")
        }
    }

    func test_sendDirectMessage_selfMessage_mapsToServerError() async throws {
        session.stub(json: #"{"error":"self_message"}"#, statusCode: 400)
        do {
            _ = try await sut.sendDirectMessage(recipientId: "me", body: "hi")
            XCTFail("Expected throw")
        } catch APIError.server(let message) {
            XCTAssertEqual(message, "self_message")
        }
    }

    // MARK: directMessage(id:)

    func test_directMessage_sendsGetToIdPath() async throws {
        session.stub(json: "{\"message\":\(dmMessageJSON)}")
        let message = try await sut.directMessage(id: "m1")
        XCTAssertEqual(session.lastRequest?.httpMethod, "GET")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/dm/m1")
        XCTAssertEqual(message.id, "m1")
    }

    // MARK: markDMRead()

    func test_markDMRead_sendsPostToReadPath() async throws {
        session.stub(json: #"{"updated":1}"#)
        let updated = try await sut.markDMRead(id: "m1")
        XCTAssertEqual(session.lastRequest?.httpMethod, "POST")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/dm/m1/read")
        XCTAssertEqual(updated, 1)
    }

    // MARK: trashDM() / restoreDM()

    func test_trashDM_sendsPostToTrashPath() async throws {
        session.stub(json: #"{"ok":true}"#)
        try await sut.trashDM(id: "m1")
        XCTAssertEqual(session.lastRequest?.httpMethod, "POST")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/dm/m1/trash")
    }

    func test_restoreDM_sendsPostToRestorePath() async throws {
        session.stub(json: #"{"ok":true}"#)
        try await sut.restoreDM(id: "m1")
        XCTAssertEqual(session.lastRequest?.httpMethod, "POST")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/dm/m1/restore")
    }

    // MARK: dmRecipients()

    func test_dmRecipients_decodesUsers() async throws {
        session.stub(json: #"{"recipients":[{"id":"u1","username":"alice","displayName":"Alice","avatar":null}]}"#)
        let recipients = try await sut.dmRecipients()
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/dm/recipients")
        XCTAssertEqual(recipients.count, 1)
        XCTAssertEqual(recipients.first?.username, "alice")
    }

    // MARK: dmThread()

    func test_dmThread_sendsGetToThreadPath() async throws {
        session.stub(json: threadJSON)
        _ = try await sut.dmThread(username: "bob")
        XCTAssertEqual(session.lastRequest?.httpMethod, "GET")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/dm/thread/bob")
    }

    func test_dmThread_decodesFlagsOtherUserAndItems() async throws {
        session.stub(json: threadJSON)
        let thread = try await sut.dmThread(username: "bob")
        XCTAssertTrue(thread.isMutual)
        XCTAssertFalse(thread.isBlocked)
        XCTAssertEqual(thread.otherUser.username, "bob")
        XCTAssertEqual(thread.items.count, 1)
        XCTAssertEqual(thread.items.first?.id, "m1")
        XCTAssertEqual(thread.olderCursor, "older1")
    }

    private var threadJSON: String {
        """
        {
          "items": [\(dmMessageJSON)],
          "olderCursor": "older1",
          "isMutual": true,
          "isBlocked": false,
          "otherUser": {"id":"r1","username":"bob","displayName":"Bob","avatar":null}
        }
        """
    }

    // MARK: dmThreadUpdates()

    func test_dmThreadUpdates_buildsAfterQuery() async throws {
        session.stub(json: threadJSON)
        _ = try await sut.dmThreadUpdates(username: "bob", after: "m1")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/dm/thread/bob/updates")
        XCTAssertTrue((session.lastRequest?.url?.query ?? "").contains("after=m1"))
    }

    // MARK: dmUnreadCount()

    func test_dmUnreadCount_decodesCount() async throws {
        session.stub(json: #"{"count":7}"#)
        let count = try await sut.dmUnreadCount()
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/dm/unread-count")
        XCTAssertEqual(count, 7)
    }

    func test_dmUnreadCount_401_throws() async throws {
        session.stub(data: Data(), statusCode: 401)
        do {
            _ = try await sut.dmUnreadCount()
            XCTFail("Expected throw")
        } catch APIError.status(let code) {
            XCTAssertEqual(code, 401)
        }
    }

    // MARK: uploadDMImage()

    func test_uploadDMImage_multipartFieldIsFile() async throws {
        session.stub(json: #"{"url":"https://cdn/img.png"}"#)
        let url = try await sut.uploadDMImage(data: Data([0x1, 0x2, 0x3]), mimeType: "image/png")
        XCTAssertEqual(session.lastRequest?.httpMethod, "POST")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/dm/images/upload")
        XCTAssertEqual(url, "https://cdn/img.png")
        let body = try XCTUnwrap(session.lastRequest?.httpBody)
        let bodyString = String(decoding: body, as: UTF8.self)
        XCTAssertTrue(bodyString.contains("name=\"file\""), "multipart field must be 'file'")
    }

    func test_uploadDMImage_setsMultipartContentType() async throws {
        session.stub(json: #"{"url":"https://cdn/img.jpg"}"#)
        _ = try await sut.uploadDMImage(data: Data([0x1]), mimeType: "image/jpeg")
        let contentType = session.lastRequest?.value(forHTTPHeaderField: "Content-Type") ?? ""
        XCTAssertTrue(contentType.hasPrefix("multipart/form-data; boundary="), "was \(contentType)")
    }
}
