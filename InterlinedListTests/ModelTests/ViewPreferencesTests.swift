import XCTest
@testable import InterlinedList

final class ViewPreferencesTests: XCTestCase {

    // MARK: FeedScope

    func test_feedScope_rawValuesMatchTheRouteLiterals() {
        // PATCH /api/user/update 400s on anything outside these four.
        XCTAssertEqual(FeedScope.allMessages.rawValue, "all_messages")
        XCTAssertEqual(FeedScope.followingOnly.rawValue, "following_only")
        XCTAssertEqual(FeedScope.followersOnly.rawValue, "followers_only")
        XCTAssertEqual(FeedScope.myMessages.rawValue, "my_messages")
    }

    func test_feedScope_from_mapsKnownValues() {
        XCTAssertEqual(FeedScope.from("following_only"), .followingOnly)
        XCTAssertEqual(FeedScope.from("my_messages"), .myMessages)
    }

    func test_feedScope_from_fallsBackForUnknownOrMissing() {
        XCTAssertEqual(FeedScope.from(nil), .allMessages)
        XCTAssertEqual(FeedScope.from(""), .allMessages)
        XCTAssertEqual(FeedScope.from("something_new_server_side"), .allMessages)
    }

    func test_feedScope_hasAPlainLanguageLabelForEveryCase() {
        for scope in FeedScope.allCases {
            XCTAssertFalse(scope.label.isEmpty)
            XCTAssertFalse(scope.label.contains("_"), "Label must not leak the wire value")
        }
    }

    // MARK: Bounds

    func test_bounds_matchTheRangesTheRouteValidates() {
        XCTAssertEqual(ViewPreferenceBounds.messagesPerPage, 10...30)
        XCTAssertEqual(ViewPreferenceBounds.notificationTrayLimit, 10...40)
    }

    func test_clamp_holdsValuesInsideTheRange() {
        XCTAssertEqual(ViewPreferenceBounds.clamp(5, to: ViewPreferenceBounds.messagesPerPage), 10)
        XCTAssertEqual(ViewPreferenceBounds.clamp(99, to: ViewPreferenceBounds.messagesPerPage), 30)
        XCTAssertEqual(ViewPreferenceBounds.clamp(20, to: ViewPreferenceBounds.messagesPerPage), 20)
        XCTAssertEqual(ViewPreferenceBounds.clamp(1, to: ViewPreferenceBounds.notificationTrayLimit), 10)
        XCTAssertEqual(ViewPreferenceBounds.clamp(100, to: ViewPreferenceBounds.notificationTrayLimit), 40)
    }
}
