import XCTest
@testable import InterlinedList

final class ShareInviteModelTests: XCTestCase {
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    func test_shareInvite_decodesAllFields() throws {
        let json = #"""
        {"token":"inv123","email":"alice@example.com","role":"collaborator","expiresAt":"2026-09-01T00:00:00Z","accepted":true,"createdAt":"2026-08-01T00:00:00Z"}
        """#
        let invite = try decoder.decode(ShareInvite.self, from: Data(json.utf8))
        XCTAssertEqual(invite.token, "inv123")
        XCTAssertEqual(invite.id, "inv123")
        XCTAssertEqual(invite.email, "alice@example.com")
        XCTAssertEqual(invite.role, "collaborator")
        XCTAssertEqual(invite.shareRole, .collaborator)
        XCTAssertEqual(invite.expiresAt, "2026-09-01T00:00:00Z")
        XCTAssertEqual(invite.accepted, true)
        XCTAssertEqual(invite.createdAt, "2026-08-01T00:00:00Z")
    }

    func test_shareInvite_missingOptionalFields_decodeNil() throws {
        let json = #"{"token":"t1","email":"bob@example.com","role":"watcher"}"#
        let invite = try decoder.decode(ShareInvite.self, from: Data(json.utf8))
        XCTAssertNil(invite.expiresAt)
        XCTAssertNil(invite.accepted)
        XCTAssertNil(invite.createdAt)
        XCTAssertEqual(invite.shareRole, .watcher)
    }

    func test_shareInvite_unknownRole_shareRoleNil() throws {
        let json = #"{"token":"t1","email":"bob@example.com","role":"owner"}"#
        let invite = try decoder.decode(ShareInvite.self, from: Data(json.utf8))
        XCTAssertNil(invite.shareRole)
    }

    func test_shareInvite_roundTrip() throws {
        let original = ShareInvite(token: "t9", email: "c@d.co", role: "manager", expiresAt: nil, accepted: false, createdAt: "2026-01-01T00:00:00Z")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ShareInvite.self, from: data)
        XCTAssertEqual(decoded.token, original.token)
        XCTAssertEqual(decoded.email, original.email)
        XCTAssertEqual(decoded.role, original.role)
        XCTAssertEqual(decoded.accepted, original.accepted)
        XCTAssertEqual(decoded.createdAt, original.createdAt)
    }

    func test_shareInvitesResponse_decodesWrapper() throws {
        let json = #"{"invites":[{"token":"t1","email":"a@b.co","role":"watcher"}]}"#
        let response = try decoder.decode(ShareInvitesResponse.self, from: Data(json.utf8))
        XCTAssertEqual(response.invites.count, 1)
        XCTAssertEqual(response.invites.first?.email, "a@b.co")
    }

    func test_createShareInviteResponse_decodes() throws {
        let json = #"{"email":"a@b.co","role":"manager","expiresAt":"2026-09-01T00:00:00Z","url":"https://interlinedlist.com/invite/x"}"#
        let response = try decoder.decode(CreateShareInviteResponse.self, from: Data(json.utf8))
        XCTAssertEqual(response.email, "a@b.co")
        XCTAssertEqual(response.shareRole, .manager)
        XCTAssertEqual(response.url, "https://interlinedlist.com/invite/x")
        XCTAssertEqual(response.expiresAt, "2026-09-01T00:00:00Z")
    }
}
