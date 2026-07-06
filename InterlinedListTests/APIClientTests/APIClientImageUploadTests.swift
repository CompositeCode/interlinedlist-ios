import XCTest
@testable import InterlinedList

final class APIClientImageUploadTests: XCTestCase {
    var sut: APIClient!
    var session: MockURLSession!

    override func setUp() {
        super.setUp()
        session = MockURLSession()
        sut = APIClient(session: session)
        sut.setBearerToken("tok")
    }

    // MARK: uploadImage()

    func test_uploadImage_sendsPostToCorrectPath() async throws {
        session.stub(json: #"{"url":"https://cdn.example.com/img.jpg"}"#)
        _ = try await sut.uploadImage(data: Data([0xFF, 0xD8]), mimeType: "image/jpeg")
        XCTAssertEqual(session.lastRequest?.httpMethod, "POST")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/messages/images/upload")
    }

    func test_uploadImage_contentTypeIsMultipart() async throws {
        session.stub(json: #"{"url":"https://cdn.example.com/img.jpg"}"#)
        _ = try await sut.uploadImage(data: Data([0xFF, 0xD8]), mimeType: "image/jpeg")
        let ct = session.lastRequest?.value(forHTTPHeaderField: "Content-Type") ?? ""
        XCTAssertTrue(ct.hasPrefix("multipart/form-data"))
    }

    func test_uploadImage_returnsURL() async throws {
        session.stub(json: #"{"url":"https://cdn.example.com/img.jpg"}"#)
        let url = try await sut.uploadImage(data: Data([0xFF, 0xD8]), mimeType: "image/jpeg")
        XCTAssertEqual(url, "https://cdn.example.com/img.jpg")
    }

    func test_uploadImage_pngUsesPngExtension() async throws {
        session.stub(json: #"{"url":"https://cdn.example.com/img.png"}"#)
        _ = try await sut.uploadImage(data: Data([0x89, 0x50]), mimeType: "image/png")
        // The multipart body carries raw (non-UTF8) image bytes, so search the raw
        // Data for the filename rather than decoding the whole body as a String.
        let body = session.lastRequest?.httpBody ?? Data()
        XCTAssertNotNil(body.range(of: Data(#"filename="upload.png""#.utf8)),
                        "Multipart body should declare a .png filename")
    }

    func test_uploadImage_403_throws() async throws {
        session.stub(data: Data(), statusCode: 403)
        do {
            _ = try await sut.uploadImage(data: Data([0xFF, 0xD8]), mimeType: "image/jpeg")
            XCTFail("Expected throw")
        } catch APIError.status(let code) {
            XCTAssertEqual(code, 403)
        }
    }

    func test_uploadImage_sendsBearerToken() async throws {
        session.stub(json: #"{"url":"https://cdn.example.com/img.jpg"}"#)
        _ = try await sut.uploadImage(data: Data([0xFF, 0xD8]), mimeType: "image/jpeg")
        XCTAssertEqual(session.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
    }

    // MARK: uploadVideo()

    func test_uploadVideo_sendsPostToCorrectPath() async throws {
        session.stub(json: #"{"url":"https://cdn.example.com/v.mp4"}"#)
        _ = try await sut.uploadVideo(data: Data([0x00, 0x00]), mimeType: "video/mp4")
        XCTAssertEqual(session.lastRequest?.httpMethod, "POST")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/messages/videos/upload")
    }

    func test_uploadVideo_mp4UsesMP4Extension() async throws {
        session.stub(json: #"{"url":"https://cdn.example.com/v.mp4"}"#)
        _ = try await sut.uploadVideo(data: Data([0x00]), mimeType: "video/mp4")
        let bodyString = String(data: session.lastRequest?.httpBody ?? Data(), encoding: .utf8) ?? ""
        XCTAssertTrue(bodyString.contains("upload.mp4"))
    }

    func test_uploadVideo_returnsURL() async throws {
        session.stub(json: #"{"url":"https://cdn.example.com/v.mp4"}"#)
        let url = try await sut.uploadVideo(data: Data([0x00]), mimeType: "video/mp4")
        XCTAssertEqual(url, "https://cdn.example.com/v.mp4")
    }

    func test_uploadVideo_403_throws() async throws {
        session.stub(data: Data(), statusCode: 403)
        do {
            _ = try await sut.uploadVideo(data: Data([0x00]), mimeType: "video/mp4")
            XCTFail("Expected throw")
        } catch APIError.status(let code) {
            XCTAssertEqual(code, 403)
        }
    }

    // MARK: uploadDocumentImage()

    func test_uploadDocumentImage_sendsPostToCorrectPath() async throws {
        session.stub(json: #"{"url":"https://cdn.example.com/doc-img.jpg"}"#)
        _ = try await sut.uploadDocumentImage(documentId: "abc123", data: Data([0xFF, 0xD8]), mimeType: "image/jpeg")
        XCTAssertEqual(session.lastRequest?.httpMethod, "POST")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/documents/abc123/images/upload")
    }

    func test_uploadDocumentImage_encodesDocumentIdInPath() async throws {
        session.stub(json: #"{"url":"https://cdn.example.com/doc-img.jpg"}"#)
        _ = try await sut.uploadDocumentImage(documentId: "doc with spaces", data: Data([0xFF, 0xD8]), mimeType: "image/jpeg")
        // url?.path is always percent-decoded by Foundation; check the raw absoluteString instead.
        let raw = session.lastRequest?.url?.absoluteString ?? ""
        XCTAssertFalse(raw.contains(" "), "URL string must not contain raw spaces")
        XCTAssertTrue(raw.hasSuffix("/images/upload"))
    }

    func test_uploadDocumentImage_contentTypeIsMultipart() async throws {
        session.stub(json: #"{"url":"https://cdn.example.com/doc-img.jpg"}"#)
        _ = try await sut.uploadDocumentImage(documentId: "abc123", data: Data([0xFF, 0xD8]), mimeType: "image/jpeg")
        let ct = session.lastRequest?.value(forHTTPHeaderField: "Content-Type") ?? ""
        XCTAssertTrue(ct.hasPrefix("multipart/form-data"))
    }

    func test_uploadDocumentImage_sendsBearerToken() async throws {
        session.stub(json: #"{"url":"https://cdn.example.com/doc-img.jpg"}"#)
        _ = try await sut.uploadDocumentImage(documentId: "abc123", data: Data([0xFF, 0xD8]), mimeType: "image/jpeg")
        XCTAssertEqual(session.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
    }

    func test_uploadDocumentImage_returnsURL() async throws {
        session.stub(json: #"{"url":"https://cdn.example.com/doc-img.jpg"}"#)
        let url = try await sut.uploadDocumentImage(documentId: "abc123", data: Data([0xFF, 0xD8]), mimeType: "image/jpeg")
        XCTAssertEqual(url, "https://cdn.example.com/doc-img.jpg")
    }

    func test_uploadDocumentImage_jpegUsesJpgExtension() async throws {
        session.stub(json: #"{"url":"https://cdn.example.com/doc-img.jpg"}"#)
        _ = try await sut.uploadDocumentImage(documentId: "abc123", data: Data([0xFF, 0xD8]), mimeType: "image/jpeg")
        let body = session.lastRequest?.httpBody ?? Data()
        XCTAssertNotNil(body.range(of: Data(#"filename="upload.jpg""#.utf8)),
                        "Multipart body should declare a .jpg filename for JPEG")
    }

    func test_uploadDocumentImage_pngUsesPngExtension() async throws {
        session.stub(json: #"{"url":"https://cdn.example.com/doc-img.png"}"#)
        _ = try await sut.uploadDocumentImage(documentId: "abc123", data: Data([0x89, 0x50]), mimeType: "image/png")
        let body = session.lastRequest?.httpBody ?? Data()
        XCTAssertNotNil(body.range(of: Data(#"filename="upload.png""#.utf8)),
                        "Multipart body should declare a .png filename for PNG")
    }

    func test_uploadDocumentImage_multipartFieldNameIsImage() async throws {
        session.stub(json: #"{"url":"https://cdn.example.com/doc-img.jpg"}"#)
        _ = try await sut.uploadDocumentImage(documentId: "abc123", data: Data([0xFF, 0xD8]), mimeType: "image/jpeg")
        let body = session.lastRequest?.httpBody ?? Data()
        XCTAssertNotNil(body.range(of: Data(#"name="image""#.utf8)),
                        "Multipart form field must be named 'image'")
    }

    func test_uploadDocumentImage_401_throwsStatusError() async throws {
        session.stub(data: Data(), statusCode: 401)
        do {
            _ = try await sut.uploadDocumentImage(documentId: "abc123", data: Data([0xFF, 0xD8]), mimeType: "image/jpeg")
            XCTFail("Expected APIError.status(401)")
        } catch APIError.status(let code) {
            XCTAssertEqual(code, 401)
        }
    }

    func test_uploadDocumentImage_403_throwsStatusError() async throws {
        session.stub(data: Data(), statusCode: 403)
        do {
            _ = try await sut.uploadDocumentImage(documentId: "abc123", data: Data([0xFF, 0xD8]), mimeType: "image/jpeg")
            XCTFail("Expected APIError.status(403)")
        } catch APIError.status(let code) {
            XCTAssertEqual(code, 403)
        }
    }

    func test_uploadDocumentImage_serverError_throwsServerError() async throws {
        session.stub(json: #"{"error":"unsupported format"}"#, statusCode: 422)
        do {
            _ = try await sut.uploadDocumentImage(documentId: "abc123", data: Data([0xFF, 0xD8]), mimeType: "image/jpeg")
            XCTFail("Expected APIError.server")
        } catch APIError.server(let msg) {
            XCTAssertEqual(msg, "unsupported format")
        }
    }
}
