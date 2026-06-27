import XCTest
@testable import InterlinedList

final class APIClientVideoUploadTests: XCTestCase {
    var sut: APIClient!
    var session: MockURLSession!

    override func setUp() {
        super.setUp()
        session = MockURLSession()
        sut = APIClient(session: session)
    }

    func test_uploadVideo_sendsMultipartToCorrectPath() async throws {
        session.stub(json: #"{"url":"https://example.com/v.mp4"}"#)
        let data = Data("fake video bytes".utf8)
        _ = try await sut.uploadVideo(data: data, mimeType: "video/mp4")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/messages/videos/upload")
        XCTAssertEqual(session.lastRequest?.httpMethod, "POST")
        let contentType = session.lastRequest?.value(forHTTPHeaderField: "Content-Type") ?? ""
        XCTAssertTrue(contentType.contains("multipart/form-data"), "Expected multipart/form-data, got: \(contentType)")
    }

    func test_uploadVideo_returnsURL() async throws {
        session.stub(json: #"{"url":"https://example.com/v.mp4"}"#)
        let data = Data("fake video bytes".utf8)
        let result = try await sut.uploadVideo(data: data, mimeType: "video/mp4")
        XCTAssertEqual(result, "https://example.com/v.mp4")
    }

    func test_uploadVideo_403_throwsStatusError() async throws {
        // A 403 with no decodable error body surfaces as `.status`; a 403 carrying a
        // `{"error":...}` body surfaces as `.server(message)` (see checkResponse and the
        // list-folder subscriber-403 test). This case exercises the status-error path.
        session.stub(data: Data(), statusCode: 403)
        let data = Data("fake video bytes".utf8)
        do {
            _ = try await sut.uploadVideo(data: data, mimeType: "video/mp4")
            XCTFail("Expected APIError.status(403)")
        } catch APIError.status(let code) {
            XCTAssertEqual(code, 403)
        }
    }
}
