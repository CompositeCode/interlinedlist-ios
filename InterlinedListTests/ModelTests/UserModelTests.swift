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
          "is_subscriber": true,
          "max_message_length": 500
        }
        """
        let user = try decoder.decode(User.self, from: Data(json.utf8))
        XCTAssertEqual(user.displayName, "Alice")
        XCTAssertEqual(user.isSubscriber, true)
        XCTAssertEqual(user.maxMessageLength, 500)
    }

    private func makeUser(displayName: String?, username: String) -> User {
        User(id: "1", email: "a@b.com", username: username,
             displayName: displayName, avatar: nil, bio: nil,
             theme: nil, emailVerified: nil, createdAt: nil,
             maxMessageLength: nil, showAdvancedPostSettings: nil,
             defaultPubliclyVisible: nil, isSubscriber: nil)
    }
}
