import XCTest
@testable import InterlinedList

final class APIClientLinkMetadataTests: XCTestCase {
    var sut: APIClient!
    var session: MockURLSession!

    override func setUp() {
        super.setUp()
        session = MockURLSession()
        sut = APIClient(session: session)
        sut.setBearerToken("tok")
    }

    func test_linkMetadata_sendsGetToCorrectPath() async throws {
        session.stub(json: #"{"link":{"url":"https://x.com","fetchStatus":"failed"}}"#)
        _ = try await sut.linkMetadata(url: "https://x.com")
        XCTAssertEqual(session.lastRequest?.httpMethod, "GET")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/link-metadata")
    }

    func test_linkMetadata_sendsUrlQueryItem() async throws {
        session.stub(json: #"{"link":{"url":"https://x.com","fetchStatus":"failed"}}"#)
        _ = try await sut.linkMetadata(url: "https://example.com/a")
        let items = URLComponents(url: session.lastRequest!.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(items.first { $0.name == "url" }?.value, "https://example.com/a")
    }

    func test_linkMetadata_percentEncodesUrlWithQueryString() async throws {
        session.stub(json: #"{"link":{"url":"https://x.com","fetchStatus":"failed"}}"#)
        _ = try await sut.linkMetadata(url: "https://x.com/p?a=1&b=2")
        // The reserved `&` in the target URL must not split into spurious params.
        let items = URLComponents(url: session.lastRequest!.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first { $0.name == "url" }?.value, "https://x.com/p?a=1&b=2")
    }

    func test_linkMetadata_decodesSuccessfulPreview() async throws {
        session.stub(json: #"""
        {"link":{
          "url":"https://example.com",
          "platform":"web",
          "fetchStatus":"success",
          "metadata":{"title":"Example","description":"A site","thumbnail":"https://example.com/og.png","type":"website"}
        }}
        """#)
        let link = try await sut.linkMetadata(url: "https://example.com")
        XCTAssertEqual(link.url, "https://example.com")
        XCTAssertEqual(link.fetchStatus, "success")
        XCTAssertEqual(link.metadata?.title, "Example")
        XCTAssertEqual(link.metadata?.description, "A site")
        XCTAssertEqual(link.metadata?.thumbnail, "https://example.com/og.png")
    }

    func test_linkMetadata_decodesFailedPreview() async throws {
        session.stub(json: #"{"link":{"url":"https://nope.example","fetchStatus":"failed","metadata":null}}"#)
        let link = try await sut.linkMetadata(url: "https://nope.example")
        XCTAssertEqual(link.fetchStatus, "failed")
        XCTAssertNil(link.metadata)
    }

    func test_linkMetadata_sendsBearerToken() async throws {
        session.stub(json: #"{"link":{"url":"https://x.com","fetchStatus":"failed"}}"#)
        _ = try await sut.linkMetadata(url: "https://x.com")
        XCTAssertEqual(session.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
    }

    func test_linkMetadata_429_withErrorBody_throwsServerError() async throws {
        // The live endpoint returns `{ error: "Too many requests" }` on 429, which
        // checkResponse maps to .server (an {error} body wins over the raw status).
        session.stub(json: #"{"error":"Too many requests"}"#, statusCode: 429)
        do {
            _ = try await sut.linkMetadata(url: "https://x.com")
            XCTFail("Expected throw")
        } catch APIError.server(let msg) {
            XCTAssertEqual(msg, "Too many requests")
        }
    }

    func test_linkMetadata_429_withoutBody_throwsStatusError() async throws {
        session.stub(data: Data(), statusCode: 429)
        do {
            _ = try await sut.linkMetadata(url: "https://x.com")
            XCTFail("Expected throw")
        } catch APIError.status(let code) {
            XCTAssertEqual(code, 429)
        }
    }

    func test_linkMetadata_400_badUrl_throwsServerError() async throws {
        session.stub(json: #"{"error":"URL must be http or https"}"#, statusCode: 400)
        do {
            _ = try await sut.linkMetadata(url: "ftp://x")
            XCTFail("Expected throw")
        } catch APIError.server(let msg) {
            XCTAssertEqual(msg, "URL must be http or https")
        }
    }
}
