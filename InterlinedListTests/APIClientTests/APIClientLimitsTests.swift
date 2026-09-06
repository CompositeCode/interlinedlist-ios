import XCTest
@testable import InterlinedList

/// P3. iOS hardcoded a 2048px image ladder while the backend resizes every
/// upload to 1200px per side, so every post shipped roughly 2.9x the pixels the
/// server kept. These tests pin the route and the decode of the caps that now
/// drive `ImageUploadProcessor`.
final class APIClientLimitsTests: XCTestCase {
    var sut: APIClient!
    var session: MockURLSession!

    override func setUp() {
        super.setUp()
        session = MockURLSession()
        sut = APIClient(session: session)
    }

    /// The live payload, verbatim.
    private var limitsJSON: String {
        #"""
        {"media":{"image":{"maxBytes":1468006,"maxPixels":1200,
                           "acceptedFormats":["jpeg","png","gif","webp"]},
                  "video":{"maxBytes":3145728,"acceptedFormats":["mp4","mov"]}},
         "message":{"maxContentLength":5000}}
        """#
    }

    func test_serverLimits_sendsGetToLimitsPath() async throws {
        session.stub(json: limitsJSON)
        _ = try await sut.serverLimits()
        XCTAssertEqual(session.lastRequest?.httpMethod, "GET")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/limits")
    }

    /// Public route — it must work before sign-in, with no token set.
    func test_serverLimits_worksWithoutABearerToken() async throws {
        session.stub(json: limitsJSON)
        let limits = try await sut.serverLimits()
        XCTAssertNil(session.lastRequest?.value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(limits.media.image.maxPixels, 1200)
    }

    func test_serverLimits_decodesImageCaps() async throws {
        session.stub(json: limitsJSON)
        let limits = try await sut.serverLimits()
        XCTAssertEqual(limits.media.image.maxBytes, 1_468_006)
        XCTAssertEqual(limits.media.image.maxPixels, 1200)
        XCTAssertEqual(limits.media.image.acceptedFormats, ["jpeg", "png", "gif", "webp"])
    }

    func test_serverLimits_decodesVideoAndMessageCaps() async throws {
        session.stub(json: limitsJSON)
        let limits = try await sut.serverLimits()
        XCTAssertEqual(limits.media.video?.maxBytes, 3_145_728)
        XCTAssertEqual(limits.message?.maxContentLength, 5000)
    }

    /// Only the image block is required; a payload without the optional sections
    /// must still decode rather than falling back wholesale.
    func test_serverLimits_decodesWithoutOptionalSections() async throws {
        session.stub(json: #"{"media":{"image":{"maxBytes":1000000,"maxPixels":800}}}"#)
        let limits = try await sut.serverLimits()
        XCTAssertEqual(limits.media.image.maxPixels, 800)
        XCTAssertNil(limits.media.video)
        XCTAssertNil(limits.message)
    }

    func test_imageUploadLimits_areDerivedFromTheServerPayload() async throws {
        session.stub(json: limitsJSON)
        let converted = ImageUploadLimits(try await sut.serverLimits())
        XCTAssertEqual(converted.maxUploadBytes, 1_468_006)
        XCTAssertEqual(converted.maxPixels, 1200)
    }
}
