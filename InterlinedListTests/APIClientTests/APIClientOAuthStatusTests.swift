import XCTest
@testable import InterlinedList

final class APIClientOAuthStatusTests: XCTestCase {
    var sut: APIClient!
    var session: MockURLSession!

    override func setUp() {
        super.setUp()
        session = MockURLSession()
        sut = APIClient(session: session)
    }

    // MARK: linkedinStatus

    func test_linkedinStatus_sendsCorrectPath() async throws {
        session.stub(json: #"{"configured":true,"redirectUri":"https://example.com/cb"}"#)
        let status = try await sut.linkedinStatus()
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/auth/linkedin/status")
        XCTAssertTrue(status.configured)
        XCTAssertEqual(status.redirectUri, "https://example.com/cb")
    }

    func test_linkedinStatus_configuredFalseWithNullRedirect() async throws {
        session.stub(json: #"{"configured":false,"redirectUri":null}"#)
        let status = try await sut.linkedinStatus()
        XCTAssertFalse(status.configured)
        XCTAssertNil(status.redirectUri)
    }

    func test_linkedinStatus_500_throws() async throws {
        session.stub(data: Data(), statusCode: 500)
        do {
            _ = try await sut.linkedinStatus()
            XCTFail("Expected throw")
        } catch APIError.status(let code) {
            XCTAssertEqual(code, 500)
        }
    }

    // MARK: twitterStatus

    func test_twitterStatus_sendsCorrectPath() async throws {
        session.stub(json: #"{"configured":false,"redirectUri":null}"#)
        let status = try await sut.twitterStatus()
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/auth/twitter/status")
        XCTAssertFalse(status.configured)
    }

    func test_twitterStatus_decodesConfigured() async throws {
        session.stub(json: #"{"configured":true,"redirectUri":"https://x/cb"}"#)
        let status = try await sut.twitterStatus()
        XCTAssertTrue(status.configured)
    }
}
