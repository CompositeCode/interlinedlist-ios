import XCTest
@testable import InterlinedList

final class APIClientSharedResolverTests: XCTestCase {
    var sut: APIClient!
    var session: MockURLSession!

    override func setUp() {
        super.setUp()
        session = MockURLSession()
        sut = APIClient(session: session)
        sut.setBearerToken("tok")
    }

    func test_resolveSharedDocument_sendsGetToTokenPath() async throws {
        session.stub(json: #"{"role":"watcher","document":{"id":"d1","title":"Doc"}}"#)
        _ = try await sut.resolveSharedDocument(token: "abc123")
        XCTAssertEqual(session.lastRequest?.httpMethod, "GET")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/documents/shared/abc123")
    }

    func test_resolveSharedDocument_percentEncodesToken() async throws {
        session.stub(json: #"{"role":"watcher","document":{"id":"d1","title":"Doc"}}"#)
        // Real tokens are hex, but a stray space must still be percent-encoded
        // (matching the project-wide `.urlPathAllowed` path-segment convention) so
        // the request URL stays valid rather than producing a malformed path.
        _ = try await sut.resolveSharedDocument(token: "a b")
        let raw = session.lastRequest?.url?.absoluteString ?? ""
        XCTAssertTrue(raw.contains("/api/documents/shared/a%20b"), "token not encoded: \(raw)")
    }

    func test_resolveSharedDocument_decodesViewerLink() async throws {
        session.stub(json: #"""
        {"role":"watcher","canClaim":false,"needsAuth":false,
         "document":{"id":"d1","title":"Shared Doc","content":"# Hi","isPublic":false,"updatedAt":"2026-08-15T00:00:00Z"}}
        """#)
        let res = try await sut.resolveSharedDocument(token: "t")
        XCTAssertEqual(res.role, "watcher")
        XCTAssertEqual(res.canClaim, false)
        XCTAssertEqual(res.document.id, "d1")
        XCTAssertEqual(res.document.title, "Shared Doc")
        XCTAssertEqual(res.document.content, "# Hi")
        XCTAssertFalse(res.isEditLink)
    }

    func test_resolveSharedDocument_editLinkIsEditLinkTrue() async throws {
        session.stub(json: #"""
        {"role":"collaborator","canClaim":false,"needsAuth":true,
         "document":{"id":"d2","title":"Editable"}}
        """#)
        let res = try await sut.resolveSharedDocument(token: "t")
        XCTAssertTrue(res.isEditLink)
        XCTAssertEqual(res.needsAuth, true)
    }

    func test_resolveSharedDocument_404_throwsServerError() async throws {
        session.stub(json: #"{"error":"Share link not found, expired, or revoked"}"#, statusCode: 404)
        do {
            _ = try await sut.resolveSharedDocument(token: "gone")
            XCTFail("Expected throw")
        } catch APIError.server(let msg) {
            XCTAssertEqual(msg, "Share link not found, expired, or revoked")
        }
    }

    func test_resolveSharedDocument_429_withoutBody_throwsStatusError() async throws {
        session.stub(data: Data(), statusCode: 429)
        do {
            _ = try await sut.resolveSharedDocument(token: "t")
            XCTFail("Expected throw")
        } catch APIError.status(let code) {
            XCTAssertEqual(code, 429)
        }
    }
}
