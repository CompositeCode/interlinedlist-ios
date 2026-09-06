import XCTest
@testable import InterlinedList

/// P3. The store is what stands between a failed `GET /api/limits` and a broken
/// upload: it must always hand back usable caps.
final class ServerLimitsStoreTests: XCTestCase {

    private func makeLimits(maxBytes: Int, maxPixels: Int) -> ServerLimits {
        ServerLimits(
            media: .init(image: .init(maxBytes: maxBytes, maxPixels: maxPixels, acceptedFormats: nil),
                         video: nil),
            message: nil
        )
    }

    func test_limits_beforeAnyRefresh_areTheDocumentedFallback() {
        let sut = ServerLimitsStore(fetch: { XCTFail("Should not fetch"); return .fallback })
        XCTAssertEqual(sut.limits, ServerLimits.fallback)
        XCTAssertEqual(sut.imageLimits.maxPixels, 1200)
        XCTAssertEqual(sut.imageLimits.maxUploadBytes, 1_400_000)
    }

    func test_refresh_adoptsTheServerCaps() async {
        let fetched = makeLimits(maxBytes: 2_000_000, maxPixels: 1600)
        let sut = ServerLimitsStore(fetch: { fetched })
        await sut.refresh()
        XCTAssertEqual(sut.limits, fetched)
        XCTAssertEqual(sut.imageLimits.maxPixels, 1600)
        XCTAssertEqual(sut.imageLimits.maxUploadBytes, 2_000_000)
    }

    /// A network failure must never block an upload — the fallback caps stand.
    func test_refresh_failure_keepsTheFallback() async {
        struct Boom: Error {}
        let sut = ServerLimitsStore(fetch: { throw Boom() })
        await sut.refresh()
        XCTAssertEqual(sut.limits, ServerLimits.fallback)
    }

    /// A later failure must not discard caps already fetched successfully.
    func test_refresh_failureAfterSuccess_keepsTheFetchedCaps() async {
        struct Boom: Error {}
        let fetched = makeLimits(maxBytes: 2_000_000, maxPixels: 1600)
        let succeeding = ServerLimitsStore(fetch: { fetched })
        await succeeding.refresh()
        XCTAssertEqual(succeeding.imageLimits.maxPixels, 1600)

        let failing = ServerLimitsStore(fetch: { throw Boom() })
        await failing.refresh()
        XCTAssertEqual(failing.imageLimits.maxPixels, 1200)
    }

    /// The store is read from a detached task inside `ImageUploadProcessor`, so
    /// concurrent reads during a refresh must not trip the lock or tear a value.
    func test_limits_areSafeToReadConcurrently() async {
        let fetched = makeLimits(maxBytes: 2_000_000, maxPixels: 1600)
        let sut = ServerLimitsStore(fetch: { fetched })
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await sut.refresh() }
            for _ in 0..<50 {
                group.addTask {
                    let pixels = sut.imageLimits.maxPixels
                    XCTAssertTrue(pixels == 1200 || pixels == 1600, "Read a torn value: \(pixels)")
                }
            }
        }
        XCTAssertEqual(sut.imageLimits.maxPixels, 1600)
    }
}
