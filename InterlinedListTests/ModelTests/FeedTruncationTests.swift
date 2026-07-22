import XCTest
@testable import InterlinedList

final class FeedTruncationTests: XCTestCase {

    func testShortStringIsUnchanged() {
        let (text, truncated) = feedTruncated("hello", limit: 10)
        XCTAssertEqual(text, "hello")
        XCTAssertFalse(truncated)
    }

    func testExactlyAtLimitIsUnchanged() {
        let input = "0123456789" // 10 characters
        let (text, truncated) = feedTruncated(input, limit: 10)
        XCTAssertEqual(text, input)
        XCTAssertFalse(truncated)
    }

    func testTruncatesAtWordBoundary() {
        let (text, truncated) = feedTruncated("hello world foobar", limit: 10)
        XCTAssertEqual(text, "hello…")
        XCTAssertTrue(truncated)
    }

    func testHardCutWhenNoWhitespace() {
        let (text, truncated) = feedTruncated("0123456789ABCDEF", limit: 10)
        XCTAssertEqual(text, "0123456789…")
        XCTAssertTrue(truncated)
    }

    func testTrailingWhitespaceIsTrimmedBeforeEllipsis() {
        // prefix(6) of "hi   thereabc" is "hi   t"; the boundary walk-back should
        // strip all trailing spaces, leaving "hi…" rather than "hi  …".
        let (text, truncated) = feedTruncated("hi   thereabc", limit: 6)
        XCTAssertEqual(text, "hi…")
        XCTAssertTrue(truncated)
    }

    func testGraphemeClustersAreNotSplit() {
        let family = "👨‍👩‍👧‍👦" // one Character, many unicode scalars
        let input = String(repeating: family, count: 3) // 3 characters
        let (text, truncated) = feedTruncated(input, limit: 2)
        XCTAssertTrue(truncated)
        XCTAssertEqual(text, family + family + "…")
        // Two family emoji plus the ellipsis — no corrupted/partial cluster.
        XCTAssertEqual(text.count, 3)
    }

    func testDefaultLimitIsTwoHundred() {
        let input = String(repeating: "a", count: 250)
        let (text, truncated) = feedTruncated(input)
        XCTAssertTrue(truncated)
        XCTAssertTrue(text.hasSuffix("…"))
        // 200 'a' characters (no whitespace to break on) + the ellipsis.
        XCTAssertEqual(text.count, 201)
    }
}
