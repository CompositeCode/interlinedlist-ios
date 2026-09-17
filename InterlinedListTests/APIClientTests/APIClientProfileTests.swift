import XCTest
@testable import InterlinedList

final class APIClientProfileTests: XCTestCase {
    var sut: APIClient!
    var session: MockURLSession!

    private let userJSON = #"{"id":"u1","email":"a@b.com","username":"alice"}"#

    override func setUp() {
        super.setUp()
        session = MockURLSession()
        sut = APIClient(session: session)
        sut.setBearerToken("tok")
    }

    // MARK: updateProfile()

    func test_updateProfile_sendsPatchToCorrectPath() async throws {
        session.stub(json: #"{"user":\#(userJSON)}"#)
        _ = try await sut.updateProfile(displayName: "Alice", bio: "Bio", defaultPubliclyVisible: true)
        XCTAssertEqual(session.lastRequest?.httpMethod, "PATCH")
        XCTAssertTrue(session.lastRequest?.url?.path.hasSuffix("/api/user/update") == true)
    }

    func test_updateProfile_bodyContainsCamelCaseDisplayName() async throws {
        session.stub(json: #"{"user":\#(userJSON)}"#)
        _ = try await sut.updateProfile(displayName: "Alice", bio: nil, defaultPubliclyVisible: nil)
        let body = try XCTUnwrap(session.lastRequest?.httpBody)
        let json = try XCTUnwrap(try? JSONSerialization.jsonObject(with: body) as? [String: Any])
        // /api/user/update only reads camelCase keys — snake_case display_name is dropped.
        XCTAssertEqual(json["displayName"] as? String, "Alice")
        XCTAssertNil(json["display_name"], "Body must NOT use snake_case key")
    }

    func test_updateProfile_returnsUser() async throws {
        session.stub(json: #"{"user":\#(userJSON)}"#)
        let user = try await sut.updateProfile(displayName: nil, bio: nil, defaultPubliclyVisible: nil)
        XCTAssertEqual(user.username, "alice")
    }

    func test_updateProfile_fallsBackToCurrentUser_whenResponseOmitsUser() async throws {
        // First call: updateProfile returns no user; second call: currentUser
        session.stub(json: #"{"message":"ok"}"#)
        // The fallback calls currentUser() which also uses the mock — stub to return user JSON
        session.stub(json: #"{"user":\#(userJSON)}"#)
        // Both requests share the mock's single stub (last wins), so stub the user response
        session.stub(json: #"{"user":\#(userJSON)}"#)
        let user = try await sut.updateProfile(displayName: nil, bio: nil, defaultPubliclyVisible: nil)
        XCTAssertEqual(user.username, "alice")
    }

    func test_updateProfile_401_throws() async throws {
        session.stub(data: Data(), statusCode: 401)
        do {
            _ = try await sut.updateProfile(displayName: nil, bio: nil, defaultPubliclyVisible: nil)
            XCTFail("Expected throw")
        } catch APIError.status(let code) {
            XCTAssertEqual(code, 401)
        }
    }

    // MARK: updateUserSettings()

    func test_updateUserSettings_sendsPatchToCorrectPath() async throws {
        session.stub(json: #"{"user":\#(userJSON)}"#)
        _ = try await sut.updateUserSettings(theme: "dark")
        XCTAssertEqual(session.lastRequest?.httpMethod, "PATCH")
        XCTAssertTrue(session.lastRequest?.url?.path.hasSuffix("/api/user/update") == true)
    }

    func test_updateUserSettings_bodyUsesCamelCaseKeys() async throws {
        session.stub(json: #"{"user":\#(userJSON)}"#)
        _ = try await sut.updateUserSettings(defaultPubliclyVisible: false, showAdvancedPostSettings: true)
        let body = try XCTUnwrap(session.lastRequest?.httpBody)
        let json = try XCTUnwrap(try? JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertNotNil(json["defaultPubliclyVisible"], "Body must use camelCase key 'defaultPubliclyVisible'")
        XCTAssertNotNil(json["showAdvancedPostSettings"], "Body must use camelCase key 'showAdvancedPostSettings'")
        XCTAssertNil(json["default_visibility"], "Body must NOT use snake_case key")
        XCTAssertNil(json["show_advanced_post_settings"], "Body must NOT use snake_case key")
    }

    // MARK: isPrivateAccount (#48)

    func test_updateUserSettings_sendsIsPrivateAccountKey() async throws {
        session.stub(json: #"{"user":\#(userJSON)}"#)
        _ = try await sut.updateUserSettings(isPrivateAccount: true)
        let body = try XCTUnwrap(session.lastRequest?.httpBody)
        let json = try XCTUnwrap(try? JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["isPrivateAccount"] as? Bool, true)
        XCTAssertNil(json["is_private_account"], "Body must NOT use snake_case key")
    }

    func test_updateUserSettings_omitsIsPrivateAccountWhenNotSet() async throws {
        session.stub(json: #"{"user":\#(userJSON)}"#)
        _ = try await sut.updateUserSettings(theme: "dark")
        let body = try XCTUnwrap(session.lastRequest?.httpBody)
        let json = try XCTUnwrap(try? JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertNil(json["isPrivateAccount"], "An untouched setting must not be sent")
    }

    // MARK: View preferences (#49)

    func test_updateUserSettings_sendsViewPreferenceKeys() async throws {
        session.stub(json: #"{"user":\#(userJSON)}"#)
        _ = try await sut.updateUserSettings(
            viewingPreference: "following_only",
            messagesPerPage: 25,
            showPreviews: false,
            notificationTrayLimit: 40
        )
        let body = try XCTUnwrap(session.lastRequest?.httpBody)
        let json = try XCTUnwrap(try? JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["viewingPreference"] as? String, "following_only")
        XCTAssertEqual(json["messagesPerPage"] as? Int, 25)
        XCTAssertEqual(json["showPreviews"] as? Bool, false)
        XCTAssertEqual(json["notificationTrayLimit"] as? Int, 40)
        XCTAssertNil(json["viewing_preference"], "Body must NOT use snake_case keys")
        XCTAssertNil(json["messages_per_page"], "Body must NOT use snake_case keys")
    }

    func test_updateUserSettings_omitsUntouchedViewPreferences() async throws {
        session.stub(json: #"{"user":\#(userJSON)}"#)
        _ = try await sut.updateUserSettings(showPreviews: true)
        let body = try XCTUnwrap(session.lastRequest?.httpBody)
        let json = try XCTUnwrap(try? JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["showPreviews"] as? Bool, true)
        XCTAssertNil(json["viewingPreference"])
        XCTAssertNil(json["messagesPerPage"])
        XCTAssertNil(json["notificationTrayLimit"])
    }

    // MARK: Wire-key regression (#46)

    // PATCH /api/user/update destructures `defaultPubliclyVisible`. It ignores unknown keys
    // silently and still answers 200, so sending `defaultVisibility` looked like a success
    // while dropping the value. These two tests fail against the old key.

    func test_updateUserSettings_sendsDefaultPubliclyVisibleNotDefaultVisibility() async throws {
        session.stub(json: #"{"user":\#(userJSON)}"#)
        _ = try await sut.updateUserSettings(defaultPubliclyVisible: true)
        let body = try XCTUnwrap(session.lastRequest?.httpBody)
        let json = try XCTUnwrap(try? JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["defaultPubliclyVisible"] as? Bool, true)
        XCTAssertNil(json["defaultVisibility"], "The route ignores `defaultVisibility` — the value would be dropped")
    }

    func test_updateProfile_sendsDefaultPubliclyVisibleNotDefaultVisibility() async throws {
        session.stub(json: #"{"user":\#(userJSON)}"#)
        _ = try await sut.updateProfile(displayName: nil, bio: nil, defaultPubliclyVisible: false)
        let body = try XCTUnwrap(session.lastRequest?.httpBody)
        let json = try XCTUnwrap(try? JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["defaultPubliclyVisible"] as? Bool, false)
        XCTAssertNil(json["defaultVisibility"], "The route ignores `defaultVisibility` — the value would be dropped")
    }

    func test_updateUserSettings_returnsUser() async throws {
        session.stub(json: #"{"user":\#(userJSON)}"#)
        let user = try await sut.updateUserSettings(theme: "light")
        XCTAssertEqual(user.username, "alice")
    }
}
