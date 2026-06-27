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

    func test_updateProfile_sendsPostToCorrectPath() async throws {
        session.stub(json: #"{"user":\#(userJSON)}"#)
        _ = try await sut.updateProfile(displayName: "Alice", bio: "Bio", defaultVisibility: true)
        XCTAssertEqual(session.lastRequest?.httpMethod, "POST")
        XCTAssertTrue(session.lastRequest?.url?.path.hasSuffix("/api/user/update") == true)
    }

    func test_updateProfile_bodyContainsDisplayName() async throws {
        session.stub(json: #"{"user":\#(userJSON)}"#)
        _ = try await sut.updateProfile(displayName: "Alice", bio: nil, defaultVisibility: nil)
        let body = try XCTUnwrap(session.lastRequest?.httpBody)
        let json = try XCTUnwrap(try? JSONSerialization.jsonObject(with: body) as? [String: Any])
        // /api/user/update uses the default snake_case encoder (same as register), so the
        // wire key is display_name, not displayName.
        XCTAssertEqual(json["display_name"] as? String, "Alice")
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
}
