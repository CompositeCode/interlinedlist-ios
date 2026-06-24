import XCTest
@testable import InterlinedList

final class UserModelTests: XCTestCase {
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    func test_displayNameOrUsername_prefersDisplayName() throws {
        let user = makeUser(displayName: "Alice Smith", username: "alice")
        XCTAssertEqual(user.displayNameOrUsername, "Alice Smith")
    }

    func test_displayNameOrUsername_fallsBackToUsername_whenDisplayNameNil() throws {
        let user = makeUser(displayName: nil, username: "alice")
        XCTAssertEqual(user.displayNameOrUsername, "alice")
    }

    func test_displayNameOrUsername_fallsBackToUsername_whenDisplayNameEmpty() throws {
        let user = makeUser(displayName: "", username: "alice")
        XCTAssertEqual(user.displayNameOrUsername, "alice")
    }

    func test_decode_snakeCaseFields() throws {
        let json = """
        {
          "id": "u1",
          "email": "a@b.com",
          "username": "alice",
          "display_name": "Alice",
          "customer_status": "subscriber:monthly",
          "max_message_length": 500
        }
        """
        let user = try decoder.decode(User.self, from: Data(json.utf8))
        XCTAssertEqual(user.displayName, "Alice")
        XCTAssertEqual(user.customerStatus, "subscriber:monthly")
        XCTAssertEqual(user.isSubscriber, true)
        XCTAssertEqual(user.maxMessageLength, 500)
    }

    func test_isSubscriber_freeStatus_isFalse() throws {
        let user = makeUser(displayName: "Alice", username: "alice", customerStatus: "free")
        XCTAssertFalse(user.isSubscriber)
    }

    func test_isSubscriber_nilStatus_isFalse() throws {
        let user = makeUser(displayName: "Alice", username: "alice", customerStatus: nil)
        XCTAssertFalse(user.isSubscriber)
    }

    func test_isSubscriber_bareSubscriberStatus_isTrue() throws {
        let user = makeUser(displayName: "Alice", username: "alice", customerStatus: "subscriber")
        XCTAssertTrue(user.isSubscriber)
    }

    func test_isSubscriber_monthlyStatus_isTrue() throws {
        let user = makeUser(displayName: "Alice", username: "alice", customerStatus: "subscriber:monthly")
        XCTAssertTrue(user.isSubscriber)
    }

    func test_isSubscriber_annualStatus_isTrue() throws {
        let user = makeUser(displayName: "Alice", username: "alice", customerStatus: "subscriber:annual")
        XCTAssertTrue(user.isSubscriber)
    }

    private func makeUser(displayName: String?, username: String, customerStatus: String? = nil) -> User {
        User(id: "1", email: "a@b.com", username: username,
             displayName: displayName, avatar: nil, bio: nil,
             theme: nil, emailVerified: nil, createdAt: nil,
             maxMessageLength: nil, showAdvancedPostSettings: nil,
             defaultPubliclyVisible: nil, customerStatus: customerStatus)
    }
}
