import XCTest
@testable import InterlinedList

final class APIClientNotificationsTests: XCTestCase {
    var sut: APIClient!
    var session: MockURLSession!

    override func setUp() {
        super.setUp()
        session = MockURLSession()
        sut = APIClient(session: session)
        sut.setBearerToken("tok")
    }

    // MARK: notifications()

    func test_notifications_sendsGetWithScopeQuery() async throws {
        session.stub(json: #"{"unread_count":2,"items":[]}"#)
        _ = try await sut.notifications()
        let url = session.lastRequest?.url?.absoluteString ?? ""
        XCTAssertTrue(url.contains("/api/notifications"))
        XCTAssertTrue(url.contains("scope=tray"))
        XCTAssertEqual(session.lastRequest?.httpMethod, "GET")
    }

    func test_notifications_decodesUnreadCount() async throws {
        session.stub(json: #"{"unread_count":5,"items":[{"id":"n1"},{"id":"n2"}]}"#)
        let resp = try await sut.notifications()
        XCTAssertEqual(resp.unreadCount, 5)
        XCTAssertEqual(resp.items.count, 2)
    }

    func test_notifications_401_throws() async throws {
        session.stub(data: Data(), statusCode: 401)
        do {
            _ = try await sut.notifications()
            XCTFail("Expected throw")
        } catch APIError.status(let code) {
            XCTAssertEqual(code, 401)
        }
    }

    // MARK: markNotificationRead()

    func test_markNotificationRead_sendsPutToCorrectPath() async throws {
        session.stub(json: #"{"ok":true}"#)
        try await sut.markNotificationRead(id: "n1")
        XCTAssertEqual(session.lastRequest?.httpMethod, "PUT")
        XCTAssertTrue(session.lastRequest?.url?.path.hasSuffix("/api/notifications/n1/read") == true)
    }

    func test_markNotificationRead_sendsBearerToken() async throws {
        session.stub(json: #"{"ok":true}"#)
        try await sut.markNotificationRead(id: "n1")
        XCTAssertEqual(session.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
    }

    // MARK: markAllNotificationsRead()

    func test_markAllNotificationsRead_sendsPostToCorrectPath() async throws {
        session.stub(json: #"{"ok":true,"updated":3}"#)
        try await sut.markAllNotificationsRead()
        XCTAssertEqual(session.lastRequest?.httpMethod, "POST")
        XCTAssertTrue(session.lastRequest?.url?.path.hasSuffix("/api/notifications/mark-all-read") == true)
    }
}
