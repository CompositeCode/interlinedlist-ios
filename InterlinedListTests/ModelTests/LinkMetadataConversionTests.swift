import XCTest
@testable import InterlinedList

/// `LinkMetadataItem.from(previews:)` bridges the two link-preview shapes: the flat
/// previews the metadata refresh returns and the nested shape the feed row renders.
/// The feed only draws a card for a non-nil `metadata`, so a preview that resolved
/// to nothing must convert to an item with no `metadata` — not an empty one.
final class LinkMetadataConversionTests: XCTestCase {

    private func preview(url: String = "https://example.com",
                         title: String? = nil,
                         description: String? = nil,
                         image: String? = nil) -> MessageLinkPreview {
        MessageLinkPreview(url: url, title: title, description: description, image: image)
    }

    // MARK: - Full previews

    func test_from_fullPreview_mapsEveryField() {
        let items = LinkMetadataItem.from(previews: [
            preview(url: "https://example.com/a", title: "T", description: "D",
                    image: "https://cdn.example.com/hero.png")
        ])

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.url, "https://example.com/a")
        XCTAssertEqual(items.first?.metadata?.title, "T")
        XCTAssertEqual(items.first?.metadata?.description, "D")
        XCTAssertEqual(items.first?.metadata?.thumbnail, "https://cdn.example.com/hero.png")
    }

    /// The flat preview carries neither, so neither is invented.
    func test_from_fullPreview_leavesPlatformAndFetchStatusNil() {
        let items = LinkMetadataItem.from(previews: [preview(title: "T")])
        XCTAssertNil(items.first?.platform)
        XCTAssertNil(items.first?.fetchStatus)
        XCTAssertNil(items.first?.metadata?.text)
        XCTAssertNil(items.first?.metadata?.type)
    }

    func test_from_multiplePreviews_preservesOrder() {
        let items = LinkMetadataItem.from(previews: [
            preview(url: "https://one.example", title: "One"),
            preview(url: "https://two.example", title: "Two"),
            preview(url: "https://three.example", title: "Three")
        ])
        XCTAssertEqual(items.map(\.url),
                       ["https://one.example", "https://two.example", "https://three.example"])
        XCTAssertEqual(items.map { $0.metadata?.title }, ["One", "Two", "Three"])
    }

    func test_from_emptyPreviews_returnsEmpty() {
        XCTAssertTrue(LinkMetadataItem.from(previews: []).isEmpty)
    }

    // MARK: - Partial previews

    func test_from_previewWithNoImageAndNoTitle_keepsUrlWithNilMetadata() {
        let items = LinkMetadataItem.from(previews: [preview(url: "https://bare.example")])

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.url, "https://bare.example")
        XCTAssertNil(items.first?.metadata)
    }

    func test_from_previewWithOnlyDescription_keepsMetadata() {
        let items = LinkMetadataItem.from(previews: [preview(description: "just a blurb")])
        XCTAssertEqual(items.first?.metadata?.description, "just a blurb")
        XCTAssertNil(items.first?.metadata?.title)
        XCTAssertNil(items.first?.metadata?.thumbnail)
    }

    func test_from_previewWithOnlyImage_keepsMetadata() {
        let items = LinkMetadataItem.from(previews: [preview(image: "https://cdn.example/x.png")])
        XCTAssertEqual(items.first?.metadata?.thumbnail, "https://cdn.example/x.png")
        XCTAssertNil(items.first?.metadata?.title)
    }

    /// The feed row already treats an empty title as nothing to draw; an all-blank
    /// preview must not sneak past the nil-metadata rule on whitespace alone.
    func test_from_previewWithBlankFields_treatsThemAsAbsent() {
        let items = LinkMetadataItem.from(previews: [
            preview(title: "", description: "   ", image: "\n")
        ])
        XCTAssertNil(items.first?.metadata)
    }

    func test_from_previewWithPaddedTitle_trimsIt() {
        let items = LinkMetadataItem.from(previews: [preview(title: "  Padded  ")])
        XCTAssertEqual(items.first?.metadata?.title, "Padded")
    }

    /// One dead preview must not suppress a live one alongside it.
    func test_from_mixedPreviews_convertsEachIndependently() {
        let items = LinkMetadataItem.from(previews: [
            preview(url: "https://dead.example"),
            preview(url: "https://live.example", title: "Live")
        ])
        XCTAssertNil(items.first?.metadata)
        XCTAssertEqual(items.last?.metadata?.title, "Live")
    }
}
