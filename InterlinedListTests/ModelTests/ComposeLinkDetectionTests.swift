import XCTest
@testable import InterlinedList

/// `firstDetectedHTTPURL(in:)` is the composer's single answer to "does this draft
/// carry a link?" — it gates both the live preview card and the post-publish
/// metadata refresh, so a link-free message must produce no request at all.
final class ComposeLinkDetectionTests: XCTestCase {

    // MARK: - Detection

    func test_firstDetectedHTTPURL_emptyContent_returnsNil() {
        XCTAssertNil(firstDetectedHTTPURL(in: ""))
    }

    func test_firstDetectedHTTPURL_plainProse_returnsNil() {
        XCTAssertNil(firstDetectedHTTPURL(in: "no links here, just words and a period."))
    }

    func test_firstDetectedHTTPURL_httpsURL_returnsAbsoluteString() {
        XCTAssertEqual(
            firstDetectedHTTPURL(in: "look at https://interlinedlist.com/about please"),
            "https://interlinedlist.com/about"
        )
    }

    func test_firstDetectedHTTPURL_httpURL_returnsAbsoluteString() {
        XCTAssertEqual(firstDetectedHTTPURL(in: "http://example.com"), "http://example.com")
    }

    func test_firstDetectedHTTPURL_multipleURLs_returnsTheFirst() {
        let text = "https://one.example.com and then https://two.example.com"
        XCTAssertEqual(firstDetectedHTTPURL(in: text), "https://one.example.com")
    }

    func test_firstDetectedHTTPURL_mailtoLink_returnsNil() {
        XCTAssertNil(firstDetectedHTTPURL(in: "mail me at someone@example.com"))
    }

    // MARK: - Publish guard

    /// The guard as `postMessage` applies it: no detected URL ⇒ no metadata request.
    private func publishAndRefreshIfLinked(
        _ content: String,
        using client: APIClient,
        messageId: String = "m1"
    ) async {
        guard firstDetectedHTTPURL(in: content) != nil else { return }
        _ = try? await client.refreshMessageMetadata(messageId: messageId)
    }

    func test_publishGuard_contentWithoutLink_issuesNoRequest() async {
        let session = MockURLSession()
        let sut = APIClient(session: session)
        sut.setBearerToken("tok")
        session.stub(json: #"{"metadata":{"links":[]}}"#)

        await publishAndRefreshIfLinked("just a thought, no links at all", using: sut)

        XCTAssertNil(session.lastRequest)
        XCTAssertTrue(session.requestHistory.isEmpty)
    }

    func test_publishGuard_contentWithLink_postsToMetadataRoute() async {
        let session = MockURLSession()
        let sut = APIClient(session: session)
        sut.setBearerToken("tok")
        session.stub(json: #"{"metadata":{"links":[{"url":"https://example.com","title":"E","description":null,"image":null}]}}"#)

        await publishAndRefreshIfLinked("read this https://example.com", using: sut, messageId: "m42")

        XCTAssertEqual(session.requestHistory.count, 1)
        XCTAssertEqual(session.lastRequest?.httpMethod, "POST")
        XCTAssertTrue(session.lastRequest?.url?.path.hasSuffix("/api/messages/m42/metadata") == true)
    }

    /// A failed refresh is swallowed on the publish path: the caller ignores the
    /// throw, so a 401 or a 500 can never surface an error after a successful post.
    func test_publishGuard_failureIsSwallowed() async {
        let session = MockURLSession()
        let sut = APIClient(session: session)
        sut.setBearerToken("tok")
        session.stub(json: #"{"error":"nope"}"#, statusCode: 500)

        await publishAndRefreshIfLinked("read this https://example.com", using: sut)

        XCTAssertEqual(session.requestHistory.count, 1)
    }
}
