import XCTest
@testable import InterlinedList

final class APIClientShareInvitesTests: XCTestCase {
    var sut: APIClient!
    var session: MockURLSession!

    private let inviteJSON = #"{"token":"inv123","email":"alice@example.com","role":"collaborator","expiresAt":"2026-09-01T00:00:00Z","accepted":false,"createdAt":"2026-08-01T00:00:00Z"}"#
    private let createJSON = #"{"email":"alice@example.com","role":"manager","expiresAt":"2026-09-01T00:00:00Z","url":"https://interlinedlist.com/invite/inv123"}"#

    override func setUp() {
        super.setUp()
        session = MockURLSession()
        sut = APIClient(session: session)
        sut.setBearerToken("tok")
    }

    private func bodyString() -> String {
        guard let data = session.lastRequest?.httpBody else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    // MARK: - shareInvites()

    func test_shareInvites_lists_sendsGetToCorrectPath() async throws {
        session.stub(json: #"{"invites":[]}"#)
        _ = try await sut.shareInvites(kind: .lists, id: "l1")
        XCTAssertEqual(session.lastRequest?.httpMethod, "GET")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/lists/l1/invites")
    }

    func test_shareInvites_documents_sendsGetToCorrectPath() async throws {
        session.stub(json: #"{"invites":[]}"#)
        _ = try await sut.shareInvites(kind: .documents, id: "d1")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/documents/d1/invites")
    }

    func test_shareInvites_decodesArray() async throws {
        session.stub(json: #"{"invites":[\#(inviteJSON)]}"#)
        let invites = try await sut.shareInvites(kind: .lists, id: "l1")
        XCTAssertEqual(invites.count, 1)
        XCTAssertEqual(invites.first?.token, "inv123")
        XCTAssertEqual(invites.first?.email, "alice@example.com")
        XCTAssertEqual(invites.first?.shareRole, .collaborator)
        XCTAssertEqual(invites.first?.accepted, false)
    }

    func test_shareInvites_sendsAuthorizationHeader() async throws {
        session.stub(json: #"{"invites":[]}"#)
        _ = try await sut.shareInvites(kind: .lists, id: "l1")
        XCTAssertEqual(session.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
    }

    func test_shareInvites_404_throwsStatus() async throws {
        session.stub(data: Data(), statusCode: 404)
        do {
            _ = try await sut.shareInvites(kind: .lists, id: "l1")
            XCTFail("Expected throw")
        } catch APIError.status(let code) {
            XCTAssertEqual(code, 404)
        }
    }

    // MARK: - createShareInvite()

    func test_createShareInvite_lists_postsToCorrectPath() async throws {
        session.stub(json: createJSON, statusCode: 201)
        _ = try await sut.createShareInvite(kind: .lists, id: "l1", email: "alice@example.com", role: .manager, expiresAt: "2026-09-01T00:00:00Z")
        XCTAssertEqual(session.lastRequest?.httpMethod, "POST")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/lists/l1/invites")
    }

    func test_createShareInvite_documents_postsToCorrectPath() async throws {
        session.stub(json: createJSON, statusCode: 201)
        _ = try await sut.createShareInvite(kind: .documents, id: "d1", email: "alice@example.com", role: .watcher)
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/documents/d1/invites")
    }

    func test_createShareInvite_bodyUsesCamelCase() async throws {
        session.stub(json: createJSON, statusCode: 201)
        _ = try await sut.createShareInvite(kind: .lists, id: "l1", email: "alice@example.com", role: .manager, expiresAt: "2026-09-01T00:00:00Z")
        let body = bodyString()
        XCTAssertTrue(body.contains("\"email\""), "expected email key, got: \(body)")
        XCTAssertTrue(body.contains("alice@example.com"))
        XCTAssertTrue(body.contains("\"role\""), "expected role key, got: \(body)")
        XCTAssertTrue(body.contains("\"manager\""))
        XCTAssertTrue(body.contains("\"expiresAt\""), "expected camelCase expiresAt, got: \(body)")
        XCTAssertFalse(body.contains("expires_at"))
    }

    func test_createShareInvite_nilExpiry_omitsField() async throws {
        session.stub(json: createJSON, statusCode: 201)
        _ = try await sut.createShareInvite(kind: .lists, id: "l1", email: "alice@example.com", role: .watcher, expiresAt: nil)
        let body = bodyString()
        XCTAssertFalse(body.contains("expiresAt"), "nil expiry should be omitted, got: \(body)")
        XCTAssertTrue(body.contains("\"email\""))
    }

    func test_createShareInvite_decodesCreateResponse() async throws {
        session.stub(json: createJSON, statusCode: 201)
        let result = try await sut.createShareInvite(kind: .lists, id: "l1", email: "alice@example.com", role: .manager)
        XCTAssertEqual(result.email, "alice@example.com")
        XCTAssertEqual(result.shareRole, .manager)
        XCTAssertEqual(result.url, "https://interlinedlist.com/invite/inv123")
        XCTAssertEqual(result.expiresAt, "2026-09-01T00:00:00Z")
    }

    func test_createShareInvite_403_throwsStatus() async throws {
        session.stub(json: #"{"error":"Subscribe to send invites"}"#, statusCode: 403)
        do {
            _ = try await sut.createShareInvite(kind: .lists, id: "l1", email: "alice@example.com", role: .watcher)
            XCTFail("Expected throw")
        } catch APIError.forbidden(let msg) {
            XCTAssertTrue(msg.contains("Subscribe"))
        } catch APIError.status(let code) {
            XCTAssertEqual(code, 403)
        } catch APIError.server(let msg) {
            XCTAssertTrue(msg.contains("Subscribe"))
        }
    }

    // MARK: - revokeShareInvite()

    func test_revokeShareInvite_lists_sendsDeleteWithToken() async throws {
        session.stub(json: #"{"revoked":true}"#)
        try await sut.revokeShareInvite(kind: .lists, id: "l1", token: "inv123")
        XCTAssertEqual(session.lastRequest?.httpMethod, "DELETE")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/lists/l1/invites/inv123")
    }

    func test_revokeShareInvite_documents_sendsDeleteWithToken() async throws {
        session.stub(json: #"{"revoked":true}"#)
        try await sut.revokeShareInvite(kind: .documents, id: "d1", token: "abc")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/documents/d1/invites/abc")
    }

    func test_revokeShareInvite_encodesTokenSpaces() async throws {
        // Matches revokeShareLink: tokens are escaped with .urlPathAllowed, which
        // percent-encodes spaces (but leaves "/" — a legal path char — intact).
        session.stub(json: #"{"revoked":true}"#)
        try await sut.revokeShareInvite(kind: .lists, id: "l1", token: "ab cd")
        let url = session.lastRequest?.url?.absoluteString ?? ""
        XCTAssertTrue(url.contains("/api/lists/l1/invites/ab%20cd"), "expected space percent-encoded, got: \(url)")
    }

    func test_revokeShareInvite_401_throws() async throws {
        session.stub(data: Data(), statusCode: 401)
        do {
            try await sut.revokeShareInvite(kind: .lists, id: "l1", token: "inv123")
            XCTFail("Expected throw")
        } catch APIError.status(let code) {
            XCTAssertEqual(code, 401)
        }
    }

    // MARK: - searchWatcherCandidates(search:)

    func test_searchWatcherCandidates_withSearch_appendsSearchParam() async throws {
        session.stub(json: #"{"users":[]}"#)
        _ = try await sut.searchWatcherCandidates(listId: "l1", search: "alice smith")
        XCTAssertEqual(session.lastRequest?.httpMethod, "GET")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/lists/l1/watchers/users")
        let url = session.lastRequest?.url?.absoluteString ?? ""
        XCTAssertTrue(url.contains("search=alice%20smith") || url.contains("search=alice+smith"), "expected percent-encoded search, got: \(url)")
    }

    func test_searchWatcherCandidates_withoutSearch_omitsSearchParam() async throws {
        session.stub(json: #"{"users":[]}"#)
        _ = try await sut.searchWatcherCandidates(listId: "l1")
        let url = session.lastRequest?.url?.absoluteString ?? ""
        XCTAssertFalse(url.contains("search="), "expected no search param, got: \(url)")
    }

    func test_searchWatcherCandidates_emptySearch_omitsSearchParam() async throws {
        session.stub(json: #"{"users":[]}"#)
        _ = try await sut.searchWatcherCandidates(listId: "l1", search: "")
        let url = session.lastRequest?.url?.absoluteString ?? ""
        XCTAssertFalse(url.contains("search="), "empty search should be omitted, got: \(url)")
    }
}
