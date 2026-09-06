import XCTest
@testable import InterlinedList

/// D4. Both avatar routes persist the avatar themselves and answer with
/// `{ url, user }`, so each call is a **single** request. The previous shape —
/// upload, then `POST /api/user/update` to apply the URL — returned 405 from the
/// PATCH-only route, so these tests pin the request count as much as the result.
final class APIClientAvatarTests: XCTestCase {
    var sut: APIClient!
    var session: MockURLSession!

    override func setUp() {
        super.setUp()
        session = MockURLSession()
        sut = APIClient(session: session)
        sut.setBearerToken("tok")
    }

    /// The live shape: the saved avatar URL plus the updated user record.
    private var avatarJSON: String {
        #"""
        {"url":"https://cdn/avatar.png",
         "user":{"id":"u1","email":"a@b.com","username":"alice","avatar":"https://cdn/avatar.png"}}
        """#
    }

    // MARK: uploadAvatar

    func test_uploadAvatar_sendsPostToCorrectPath() async throws {
        session.stub(json: avatarJSON)
        _ = try await sut.uploadAvatar(data: Data([0xFF, 0xD8]), mimeType: "image/jpeg")
        XCTAssertEqual(session.requestHistory.first?.httpMethod, "POST")
        XCTAssertEqual(session.requestHistory.first?.url?.path, "/api/user/avatar/upload")
    }

    func test_uploadAvatar_makesExactlyOneRequest() async throws {
        session.stub(json: avatarJSON)
        _ = try await sut.uploadAvatar(data: Data([0xFF, 0xD8]), mimeType: "image/jpeg")
        XCTAssertEqual(session.requestHistory.count, 1,
                       "The upload response already carries the saved user — a second write 405s")
    }

    func test_uploadAvatar_neverPostsToUserUpdate() async throws {
        session.stub(json: avatarJSON)
        _ = try await sut.uploadAvatar(data: Data([0xFF, 0xD8]), mimeType: "image/jpeg")
        XCTAssertFalse(session.requestHistory.contains { $0.url?.path == "/api/user/update" },
                       "/api/user/update exports PATCH only; POSTing it returns 405")
    }

    func test_uploadAvatar_usesMultipart() async throws {
        session.stub(json: avatarJSON)
        _ = try await sut.uploadAvatar(data: Data([0xFF]), mimeType: "image/png")
        let ct = session.requestHistory.first?.value(forHTTPHeaderField: "Content-Type") ?? ""
        XCTAssertTrue(ct.hasPrefix("multipart/form-data"))
    }

    func test_uploadAvatar_pngUsesPngExtension() async throws {
        session.stub(json: avatarJSON)
        _ = try await sut.uploadAvatar(data: Data([0x89]), mimeType: "image/png")
        // The multipart body carries raw (non-UTF8) image bytes, so search the raw
        // Data for the filename rather than decoding the whole body as a String.
        let body = session.requestHistory.first?.httpBody ?? Data()
        XCTAssertNotNil(body.range(of: Data(#"filename="avatar.png""#.utf8)),
                        "Multipart body should declare a .png filename")
    }

    func test_uploadAvatar_returnsUserFromUploadResponse() async throws {
        session.stub(json: avatarJSON)
        let user = try await sut.uploadAvatar(data: Data([0xFF]), mimeType: "image/jpeg")
        XCTAssertEqual(user.id, "u1")
        XCTAssertEqual(user.avatar, "https://cdn/avatar.png")
    }

    /// Tolerates a deployment that answers with the bare `{ url }`: fall back to
    /// re-reading the profile rather than returning a stale avatar.
    func test_uploadAvatar_withoutUserInResponse_fallsBackToCurrentUser() async throws {
        session.enqueue(json: #"{"url":"https://cdn/x.jpg"}"#)
        session.enqueue(json: #"{"user":{"id":"u1","email":"a@b.com","username":"alice","avatar":"https://cdn/x.jpg"}}"#)
        let user = try await sut.uploadAvatar(data: Data([0xFF]), mimeType: "image/jpeg")
        XCTAssertEqual(user.avatar, "https://cdn/x.jpg")
        XCTAssertEqual(session.requestHistory.count, 2)
        XCTAssertEqual(session.requestHistory.last?.url?.path, "/api/user")
    }

    func test_uploadAvatar_403_throws() async throws {
        session.stub(data: Data(), statusCode: 403)
        do {
            _ = try await sut.uploadAvatar(data: Data([0xFF]), mimeType: "image/jpeg")
            XCTFail("Expected throw")
        } catch APIError.status(let code) {
            XCTAssertEqual(code, 403)
        }
    }

    // MARK: setAvatarFromURL

    func test_setAvatarFromURL_sendsCorrectPath() async throws {
        session.stub(json: avatarJSON)
        _ = try await sut.setAvatarFromURL("https://external/img.png")
        XCTAssertEqual(session.requestHistory.first?.url?.path, "/api/user/avatar/from-url")
        XCTAssertEqual(session.requestHistory.first?.httpMethod, "POST")
    }

    func test_setAvatarFromURL_makesExactlyOneRequest() async throws {
        session.stub(json: avatarJSON)
        _ = try await sut.setAvatarFromURL("https://external/img.png")
        XCTAssertEqual(session.requestHistory.count, 1)
        XCTAssertFalse(session.requestHistory.contains { $0.url?.path == "/api/user/update" })
    }

    func test_setAvatarFromURL_bodyContainsURL() async throws {
        session.stub(json: avatarJSON)
        _ = try await sut.setAvatarFromURL("https://external/img.png")
        let body = String(data: session.requestHistory.first?.httpBody ?? Data(), encoding: .utf8) ?? ""
        XCTAssertTrue(body.contains("\"url\":\"https:\\/\\/external\\/img.png\""))
    }

    func test_setAvatarFromURL_returnsUserFromResponse() async throws {
        session.stub(json: avatarJSON)
        let user = try await sut.setAvatarFromURL("https://external/img.png")
        XCTAssertEqual(user.id, "u1")
        XCTAssertEqual(user.avatar, "https://cdn/avatar.png")
    }

    func test_setAvatarFromURL_withoutUserInResponse_fallsBackToCurrentUser() async throws {
        session.enqueue(json: #"{"url":"https://cdn/x.png"}"#)
        session.enqueue(json: #"{"user":{"id":"u1","email":"a@b.com","username":"alice","avatar":"https://cdn/x.png"}}"#)
        let user = try await sut.setAvatarFromURL("https://external/img.png")
        XCTAssertEqual(user.avatar, "https://cdn/x.png")
        XCTAssertEqual(session.requestHistory.count, 2)
        XCTAssertEqual(session.requestHistory.last?.url?.path, "/api/user")
    }
}
