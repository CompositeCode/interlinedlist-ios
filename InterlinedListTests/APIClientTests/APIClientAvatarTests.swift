import XCTest
@testable import InterlinedList

final class APIClientAvatarTests: XCTestCase {
    var sut: APIClient!
    var session: MockURLSession!

    override func setUp() {
        super.setUp()
        session = MockURLSession()
        sut = APIClient(session: session)
        sut.setBearerToken("tok")
    }

    private var userJSON: String {
        #"{"user":{"id":"u1","email":"a@b.com","username":"alice","avatar":"https://cdn/avatar.png"}}"#
    }

    // MARK: uploadAvatar

    func test_uploadAvatar_sendsPostToCorrectPath() async throws {
        session.enqueue(json: #"{"url":"https://cdn/avatar.png"}"#)
        session.enqueue(json: userJSON)
        _ = try await sut.uploadAvatar(data: Data([0xFF, 0xD8]), mimeType: "image/jpeg")
        // First request is the upload; track via requestHistory.
        XCTAssertEqual(session.requestHistory.first?.httpMethod, "POST")
        XCTAssertEqual(session.requestHistory.first?.url?.path, "/api/user/avatar/upload")
    }

    func test_uploadAvatar_usesMultipart() async throws {
        session.enqueue(json: #"{"url":"https://cdn/x.png"}"#)
        session.enqueue(json: userJSON)
        _ = try await sut.uploadAvatar(data: Data([0xFF]), mimeType: "image/png")
        let ct = session.requestHistory.first?.value(forHTTPHeaderField: "Content-Type") ?? ""
        XCTAssertTrue(ct.hasPrefix("multipart/form-data"))
    }

    func test_uploadAvatar_pngUsesPngExtension() async throws {
        session.enqueue(json: #"{"url":"https://cdn/x.png"}"#)
        session.enqueue(json: userJSON)
        _ = try await sut.uploadAvatar(data: Data([0x89]), mimeType: "image/png")
        let body = String(data: session.requestHistory.first?.httpBody ?? Data(), encoding: .utf8) ?? ""
        XCTAssertTrue(body.contains("avatar.png"))
    }

    func test_uploadAvatar_returnsUser() async throws {
        session.enqueue(json: #"{"url":"https://cdn/x.jpg"}"#)
        session.enqueue(json: userJSON)
        let user = try await sut.uploadAvatar(data: Data([0xFF]), mimeType: "image/jpeg")
        XCTAssertEqual(user.id, "u1")
        XCTAssertEqual(user.avatar, "https://cdn/avatar.png")
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
        session.enqueue(json: #"{"url":"https://cdn/x.png"}"#)
        session.enqueue(json: userJSON)
        _ = try await sut.setAvatarFromURL("https://external/img.png")
        XCTAssertEqual(session.requestHistory.first?.url?.path, "/api/user/avatar/from-url")
        XCTAssertEqual(session.requestHistory.first?.httpMethod, "POST")
    }

    func test_setAvatarFromURL_bodyContainsURL() async throws {
        session.enqueue(json: #"{"url":"https://cdn/x.png"}"#)
        session.enqueue(json: userJSON)
        _ = try await sut.setAvatarFromURL("https://external/img.png")
        let body = String(data: session.requestHistory.first?.httpBody ?? Data(), encoding: .utf8) ?? ""
        XCTAssertTrue(body.contains("\"url\":\"https:\\/\\/external\\/img.png\""))
    }

    func test_setAvatarFromURL_returnsUser() async throws {
        session.enqueue(json: #"{"url":"https://cdn/x.png"}"#)
        session.enqueue(json: userJSON)
        let user = try await sut.setAvatarFromURL("https://external/img.png")
        XCTAssertEqual(user.id, "u1")
    }
}
