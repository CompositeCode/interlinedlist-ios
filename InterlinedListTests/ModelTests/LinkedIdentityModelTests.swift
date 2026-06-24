import XCTest
@testable import InterlinedList

final class LinkedIdentityModelTests: XCTestCase {
    func test_decode_fullObject() throws {
        let json = #"{"id":"a1","provider":"github","providerUsername":"octo","createdAt":"2026-01-01T00:00:00Z"}"#
        let identity = try JSONDecoder().decode(APIClient.LinkedIdentity.self, from: Data(json.utf8))
        XCTAssertEqual(identity.id, "a1")
        XCTAssertEqual(identity.provider, "github")
        XCTAssertEqual(identity.providerUsername, "octo")
        XCTAssertEqual(identity.createdAt, "2026-01-01T00:00:00Z")
    }

    func test_decode_nullProviderUsername() throws {
        let json = #"{"id":"a1","provider":"bluesky","providerUsername":null,"createdAt":null}"#
        let identity = try JSONDecoder().decode(APIClient.LinkedIdentity.self, from: Data(json.utf8))
        XCTAssertNil(identity.providerUsername)
        XCTAssertNil(identity.createdAt)
    }

    func test_roundTrip() throws {
        let original = APIClient.LinkedIdentity(
            id: "a1",
            provider: "github",
            providerUsername: "octocat",
            createdAt: "2026-01-01T00:00:00Z"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(APIClient.LinkedIdentity.self, from: data)
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.provider, original.provider)
        XCTAssertEqual(decoded.providerUsername, original.providerUsername)
        XCTAssertEqual(decoded.createdAt, original.createdAt)
    }
}
