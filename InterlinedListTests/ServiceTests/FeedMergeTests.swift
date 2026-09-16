import XCTest
@testable import InterlinedList

/// `Message`'s `==` is identity-based (id only), so every assertion here compares
/// content fields explicitly — comparing whole `Message` values would pass even when
/// the merge kept a stale row.
final class FeedMergeTests: XCTestCase {

    // MARK: - In-place updates

    func test_merge_existingRowWithNewContent_isReplacedInPlace() {
        let existing = [makeMessage(id: "a", content: "before"), makeMessage(id: "b")]
        let incoming = [makeMessage(id: "a", content: "after"), makeMessage(id: "b")]

        let result = FeedMerge.merge(existing: existing, incoming: incoming)

        XCTAssertEqual(result.messages.map(\.id), ["a", "b"])
        XCTAssertEqual(result.messages.first?.content, "after")
    }

    func test_merge_existingRowWithNewContent_isNotDuplicated() {
        let existing = [makeMessage(id: "a", content: "before")]
        let incoming = [makeMessage(id: "a", content: "after")]

        let result = FeedMerge.merge(existing: existing, incoming: incoming)

        XCTAssertEqual(result.messages.count, 1)
    }

    func test_merge_replacedRow_keepsItsPosition() {
        let existing = [makeMessage(id: "a"), makeMessage(id: "b", content: "before"), makeMessage(id: "c")]
        let incoming = [makeMessage(id: "b", content: "after")]

        let result = FeedMerge.merge(existing: existing, incoming: incoming)

        XCTAssertEqual(result.messages.map(\.id), ["a", "b", "c"])
        XCTAssertEqual(result.messages[1].content, "after")
    }

    func test_merge_linkMetadataBackfill_isVisibleOnTheHeldRow() {
        let existing = [makeMessage(id: "a")]
        let backfilled = makeMessage(
            id: "a",
            linkMetadata: LinkMetadata(links: [
                LinkMetadataItem(
                    url: "https://example.com",
                    platform: nil,
                    metadata: LinkMetadataItemContent(thumbnail: nil, title: "Example",
                                                      description: nil, text: nil, type: nil),
                    fetchStatus: nil
                )
            ])
        )

        let result = FeedMerge.merge(existing: existing, incoming: [backfilled])

        XCTAssertEqual(result.messages.first?.linkMetadata?.links.first?.metadata?.title, "Example")
    }

    func test_merge_replacedRow_isReportedAsChanged() {
        let result = FeedMerge.merge(existing: [makeMessage(id: "a", content: "before")],
                                     incoming: [makeMessage(id: "a", content: "after")])

        XCTAssertEqual(result.changed.map(\.id), ["a"])
        XCTAssertEqual(result.changed.first?.content, "after")
    }

    // MARK: - Insertions

    func test_merge_unseenId_isPrependedNewestFirst() {
        let existing = [makeMessage(id: "old")]
        let incoming = [makeMessage(id: "new"), makeMessage(id: "old")]

        let result = FeedMerge.merge(existing: existing, incoming: incoming)

        XCTAssertEqual(result.messages.map(\.id), ["new", "old"])
    }

    func test_merge_severalUnseenIds_keepIncomingOrder() {
        let existing = [makeMessage(id: "old")]
        let incoming = [makeMessage(id: "n1"), makeMessage(id: "n2"), makeMessage(id: "old")]

        let result = FeedMerge.merge(existing: existing, incoming: incoming)

        XCTAssertEqual(result.messages.map(\.id), ["n1", "n2", "old"])
    }

    func test_merge_insertedRow_isReportedAsChanged() {
        let result = FeedMerge.merge(existing: [makeMessage(id: "old")],
                                     incoming: [makeMessage(id: "new")])

        XCTAssertTrue(result.changed.contains { $0.id == "new" })
    }

    // MARK: - Rows the store does not hold

    func test_merge_paginatedRowsNotInIncoming_areKept() {
        // Page 2+ is appended by the view and never reaches the store.
        let existing = [makeMessage(id: "p1"), makeMessage(id: "p2"), makeMessage(id: "p3")]
        let incoming = [makeMessage(id: "p1")]

        let result = FeedMerge.merge(existing: existing, incoming: incoming)

        XCTAssertEqual(result.messages.map(\.id), ["p1", "p2", "p3"])
    }

    func test_merge_emptyIncoming_changesNothing() {
        let existing = [makeMessage(id: "a"), makeMessage(id: "b")]

        let result = FeedMerge.merge(existing: existing, incoming: [])

        XCTAssertEqual(result.messages.map(\.id), ["a", "b"])
        XCTAssertTrue(result.changed.isEmpty)
    }

    func test_merge_emptyExisting_takesIncomingAsIs() {
        let result = FeedMerge.merge(existing: [], incoming: [makeMessage(id: "a"), makeMessage(id: "b")])

        XCTAssertEqual(result.messages.map(\.id), ["a", "b"])
        XCTAssertEqual(result.changed.map(\.id), ["a", "b"])
    }

    func test_merge_identicalInput_reportsTheRowsItRefreshed() {
        let existing = [makeMessage(id: "a"), makeMessage(id: "b")]

        let result = FeedMerge.merge(existing: existing, incoming: existing)

        XCTAssertEqual(result.messages.map(\.id), ["a", "b"])
        XCTAssertEqual(result.changed.count, 2)
    }

    // MARK: - Helpers

    private func makeMessage(id: String,
                             content: String = "test",
                             linkMetadata: LinkMetadata? = nil) -> Message {
        Message(id: id, content: content, publiclyVisible: true,
                userId: "u1", createdAt: "2026-01-01T00:00:00Z",
                updatedAt: nil, user: nil, imageUrls: nil, videoUrls: nil,
                linkMetadata: linkMetadata, parentId: nil, scheduledAt: nil,
                tags: nil, digCount: 0, dugByMe: false, crossPostUrls: nil)
    }
}
