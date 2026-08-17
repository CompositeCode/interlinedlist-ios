import XCTest
@testable import InterlinedList

final class DirectMessageModelTests: XCTestCase {
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    // MARK: DMMessage

    func test_dmMessage_decodesFullPayload() throws {
        let json = """
        {
          "id": "m1",
          "pairKey": "a:b",
          "senderId": "s1",
          "recipientId": "r1",
          "body": "hi **there**",
          "imageUrls": ["https://img/1.png","https://img/2.png"],
          "createdAt": "2026-07-31T12:00:00.000Z",
          "readAt": "2026-07-31T12:05:00.000Z",
          "sender": {"id":"s1","username":"alice","displayName":"Alice","avatar":"a.png"},
          "recipient": {"id":"r1","username":"bob","displayName":null,"avatar":null},
          "preview": "hi there"
        }
        """
        let message = try decoder.decode(DMMessage.self, from: Data(json.utf8))
        XCTAssertEqual(message.id, "m1")
        XCTAssertEqual(message.senderId, "s1")
        XCTAssertEqual(message.recipientId, "r1")
        XCTAssertEqual(message.imageUrls.count, 2)
        XCTAssertEqual(message.sender?.username, "alice")
        XCTAssertEqual(message.recipient?.username, "bob")
        XCTAssertTrue(message.isRead)
    }

    func test_dmMessage_missingOptionalsDoNotCrash() throws {
        let json = """
        {
          "id": "m2",
          "senderId": "s1",
          "recipientId": "r1",
          "createdAt": "2026-07-31T12:00:00.000Z"
        }
        """
        let message = try decoder.decode(DMMessage.self, from: Data(json.utf8))
        XCTAssertEqual(message.id, "m2")
        XCTAssertEqual(message.body, "")
        XCTAssertTrue(message.imageUrls.isEmpty)
        XCTAssertNil(message.readAt)
        XCTAssertNil(message.sender)
        XCTAssertNil(message.preview)
        XCTAssertFalse(message.isRead)
    }

    func test_dmMessage_nullReadAt_isUnread() throws {
        let json = """
        {"id":"m3","senderId":"s1","recipientId":"r1","body":"x","createdAt":"t","readAt":null}
        """
        let message = try decoder.decode(DMMessage.self, from: Data(json.utf8))
        XCTAssertFalse(message.isRead)
    }

    func test_dmMessage_otherParty_returnsRecipientWhenSelfIsSender() throws {
        let json = """
        {
          "id":"m4","senderId":"me","recipientId":"r1","body":"x","createdAt":"t",
          "sender":{"id":"me","username":"self","displayName":null,"avatar":null},
          "recipient":{"id":"r1","username":"bob","displayName":null,"avatar":null}
        }
        """
        let message = try decoder.decode(DMMessage.self, from: Data(json.utf8))
        XCTAssertEqual(message.otherParty(selfId: "me")?.username, "bob")
    }

    func test_dmMessage_otherParty_returnsSenderWhenSelfIsRecipient() throws {
        let json = """
        {
          "id":"m5","senderId":"s1","recipientId":"me","body":"x","createdAt":"t",
          "sender":{"id":"s1","username":"alice","displayName":null,"avatar":null},
          "recipient":{"id":"me","username":"self","displayName":null,"avatar":null}
        }
        """
        let message = try decoder.decode(DMMessage.self, from: Data(json.utf8))
        XCTAssertEqual(message.otherParty(selfId: "me")?.username, "alice")
    }

    // MARK: DMUser

    func test_dmUser_displayNameOrUsername_fallsBackToUsername() throws {
        let json = #"{"id":"u1","username":"alice","displayName":"","avatar":null}"#
        let user = try decoder.decode(DMUser.self, from: Data(json.utf8))
        XCTAssertEqual(user.displayNameOrUsername, "alice")
    }

    func test_dmUser_displayNameOrUsername_prefersDisplayName() throws {
        let json = #"{"id":"u1","username":"alice","displayName":"Alice A","avatar":null}"#
        let user = try decoder.decode(DMUser.self, from: Data(json.utf8))
        XCTAssertEqual(user.displayNameOrUsername, "Alice A")
    }

    // MARK: DMThread

    func test_dmThread_decodesFlagsAndItems() throws {
        let json = """
        {
          "items": [{"id":"m1","senderId":"s1","recipientId":"r1","body":"hi","createdAt":"t"}],
          "olderCursor": "c1",
          "isMutual": true,
          "isBlocked": false,
          "otherUser": {"id":"r1","username":"bob","displayName":"Bob","avatar":null}
        }
        """
        let thread = try decoder.decode(DMThread.self, from: Data(json.utf8))
        XCTAssertEqual(thread.items.count, 1)
        XCTAssertEqual(thread.olderCursor, "c1")
        XCTAssertTrue(thread.isMutual)
        XCTAssertFalse(thread.isBlocked)
        XCTAssertEqual(thread.otherUser.username, "bob")
    }

    func test_dmThread_missingFlagsDefaultToFalse() throws {
        let json = """
        {
          "items": [],
          "otherUser": {"id":"r1","username":"bob","displayName":null,"avatar":null}
        }
        """
        let thread = try decoder.decode(DMThread.self, from: Data(json.utf8))
        XCTAssertTrue(thread.items.isEmpty)
        XCTAssertFalse(thread.isMutual)
        XCTAssertFalse(thread.isBlocked)
        XCTAssertNil(thread.olderCursor)
    }

    // MARK: DMFolder

    func test_dmFolder_rawValuesMatchAPIContract() {
        XCTAssertEqual(DMFolder.inbox.rawValue, "inbox")
        XCTAssertEqual(DMFolder.sent.rawValue, "sent")
        XCTAssertEqual(DMFolder.deleted.rawValue, "deleted")
        XCTAssertEqual(DMFolder.allCases.count, 3)
    }

    // MARK: DMRecipientFilter

    private func user(_ username: String, _ displayName: String? = nil) -> DMUser {
        DMUser(id: username, username: username, displayName: displayName, avatar: nil)
    }

    func test_recipientFilter_blankQuery_returnsEveryone() {
        let people = [user("alice"), user("bob")]
        XCTAssertEqual(DMRecipientFilter.matches(people, query: "").count, 2)
        XCTAssertEqual(DMRecipientFilter.matches(people, query: "   ").count, 2)
    }

    func test_recipientFilter_matchesUsernameCaseInsensitively() {
        let people = [user("alice"), user("bob")]
        let result = DMRecipientFilter.matches(people, query: "ALI")
        XCTAssertEqual(result.map(\.username), ["alice"])
    }

    func test_recipientFilter_matchesDisplayName() {
        let people = [user("alice", "Alice Anderson"), user("bob", "Bob Brown")]
        let result = DMRecipientFilter.matches(people, query: "brown")
        XCTAssertEqual(result.map(\.username), ["bob"])
    }

    func test_recipientFilter_noMatch_returnsEmpty() {
        let people = [user("alice"), user("bob")]
        XCTAssertTrue(DMRecipientFilter.matches(people, query: "zzz").isEmpty)
    }
}
