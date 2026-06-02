import XCTest
@testable import InterlinedList

final class AppNotificationCodableTests: XCTestCase {
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    func test_decode_allFields() throws {
        let json = #"""
        {"id":"n1","message":"Alice followed you","type":"follow","read":false,
         "created_at":"2024-01-01T00:00:00Z","actor_username":"alice"}
        """#
        let n = try decoder.decode(AppNotification.self, from: Data(json.utf8))
        XCTAssertEqual(n.id, "n1")
        XCTAssertEqual(n.message, "Alice followed you")
        XCTAssertEqual(n.type, "follow")
        XCTAssertEqual(n.read, false)
        XCTAssertEqual(n.actorUsername, "alice")
    }

    func test_decode_optionalFieldsAbsent() throws {
        let json = #"{"id":"n2"}"#
        let n = try decoder.decode(AppNotification.self, from: Data(json.utf8))
        XCTAssertNil(n.message)
        XCTAssertNil(n.type)
        XCTAssertNil(n.read)
        XCTAssertNil(n.actorUsername)
    }

    func test_decode_notificationsResponse() throws {
        let json = #"""
        {"unread_count":3,"items":[{"id":"n1"},{"id":"n2"},{"id":"n3"}]}
        """#
        let r = try decoder.decode(NotificationsResponse.self, from: Data(json.utf8))
        XCTAssertEqual(r.unreadCount, 3)
        XCTAssertEqual(r.items.count, 3)
    }

    func test_decode_notificationsResponse_emptyItems() throws {
        let json = #"{"unread_count":0,"items":[]}"#
        let r = try decoder.decode(NotificationsResponse.self, from: Data(json.utf8))
        XCTAssertEqual(r.unreadCount, 0)
        XCTAssertTrue(r.items.isEmpty)
    }
}
