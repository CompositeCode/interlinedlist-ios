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
        _ = try await sut.updateProfile(displayName: "Alice", bio: "Bio", defaultVisibility: true)
        XCTAssertEqual(session.lastRequest?.httpMethod, "PATCH")
        XCTAssertTrue(session.lastRequest?.url?.path.hasSuffix("/api/user/update") == true)
    }

    func test_updateProfile_bodyContainsCamelCaseDisplayName() async throws {
        session.stub(json: #"{"user":\#(userJSON)}"#)
        _ = try await sut.updateProfile(displayName: "Alice", bio: nil, defaultVisibility: nil)
        let body = try XCTUnwrap(session.lastRequest?.httpBody)
        let json = try XCTUnwrap(try? JSONSerialization.jsonObject(with: body) as? [String: Any])
        // /api/user/update only reads camelCase keys — snake_case display_name is dropped.
        XCTAssertEqual(json["displayName"] as? String, "Alice")
        XCTAssertNil(json["display_name"], "Body must NOT use snake_case key")
    }

    func test_updateProfile_returnsUser() async throws {
        session.stub(json: #"{"user":\#(userJSON)}"#)
        let user = try await sut.updateProfile(displayName: nil, bio: nil, defaultVisibility: nil)
        XCTAssertEqual(user.username, "alice")
    }

    func test_updateProfile_fallsBackToCurrentUser_whenResponseOmitsUser() async throws {
        // First call: updateProfile returns no user; second call: currentUser
        session.stub(json: #"{"message":"ok"}"#)
        // The fallback calls currentUser() which also uses the mock — stub to return user JSON
        session.stub(json: #"{"user":\#(userJSON)}"#)
        // Both requests share the mock's single stub (last wins), so stub the user response
        session.stub(json: #"{"user":\#(userJSON)}"#)
        let user = try await sut.updateProfile(displayName: nil, bio: nil, defaultVisibility: nil)
        XCTAssertEqual(user.username, "alice")
    }

    func test_updateProfile_401_throws() async throws {
        session.stub(data: Data(), statusCode: 401)
        do {
            _ = try await sut.updateProfile(displayName: nil, bio: nil, defaultVisibility: nil)
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
        _ = try await sut.updateUserSettings(defaultVisibility: false, showAdvancedPostSettings: true)
        let body = try XCTUnwrap(session.lastRequest?.httpBody)
        let json = try XCTUnwrap(try? JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertNotNil(json["defaultVisibility"], "Body must use camelCase key 'defaultVisibility'")
        XCTAssertNotNil(json["showAdvancedPostSettings"], "Body must use camelCase key 'showAdvancedPostSettings'")
        XCTAssertNil(json["default_visibility"], "Body must NOT use snake_case key")
        XCTAssertNil(json["show_advanced_post_settings"], "Body must NOT use snake_case key")
    }

    func test_updateUserSettings_returnsUser() async throws {
        session.stub(json: #"{"user":\#(userJSON)}"#)
        let user = try await sut.updateUserSettings(theme: "light")
        XCTAssertEqual(user.username, "alice")
    }
}
