import XCTest
@testable import InterlinedList

final class MarkdownBlockTests: XCTestCase {

    // The core fix: an inserted image line must become an image block (which the
    // renderer draws with AsyncImage), not get dropped like AttributedString did.
    func testStandaloneImageBecomesImageBlock() {
        let blocks = MarkdownBlock.parse("![diagram](https://example.com/a.jpg)")
        XCTAssertEqual(blocks.count, 1)
        guard case let .image(alt, url) = blocks[0] else {
            return XCTFail("expected image block, got \(blocks)")
        }
        XCTAssertEqual(alt, "diagram")
        XCTAssertEqual(url, "https://example.com/a.jpg")
    }

    // The real document scenario: prose with an image appended on its own line.
    func testParagraphThenImage() {
        let blocks = MarkdownBlock.parse("Some notes here.\n\n![image](https://example.com/b.png)")
        XCTAssertEqual(blocks.count, 2)
        guard case .paragraph = blocks[0] else {
            return XCTFail("expected paragraph first, got \(blocks)")
        }
        guard case let .image(_, url) = blocks[1] else {
            return XCTFail("expected image second, got \(blocks)")
        }
        XCTAssertEqual(url, "https://example.com/b.png")
    }

    func testEmptyAltImageParses() {
        let blocks = MarkdownBlock.parse("![](https://example.com/c.jpg)")
        guard case let .image(alt, url) = blocks.first else {
            return XCTFail("expected image block, got \(blocks)")
        }
        XCTAssertEqual(alt, "")
        XCTAssertEqual(url, "https://example.com/c.jpg")
    }

    func testMalformedImageIsParagraph() {
        // Missing closing paren — treat as text, never a broken image block.
        let blocks = MarkdownBlock.parse("![oops](https://example.com/x")
        guard case .paragraph = blocks.first else {
            return XCTFail("expected paragraph, got \(blocks)")
        }
    }

    func testHeadingLevels() {
        let blocks = MarkdownBlock.parse("# One\n## Two\n### Three")
        XCTAssertEqual(blocks.count, 3)
        let levels = blocks.compactMap { block -> Int? in
            if case let .heading(level, _) = block { return level }
            return nil
        }
        XCTAssertEqual(levels, [1, 2, 3])
    }

    func testBulletListGroupsConsecutiveItems() {
        let blocks = MarkdownBlock.parse("- a\n- b\n- c")
        XCTAssertEqual(blocks.count, 1)
        guard case let .bulletList(items) = blocks[0] else {
            return XCTFail("expected bullet list, got \(blocks)")
        }
        XCTAssertEqual(items, ["a", "b", "c"])
    }

    func testOrderedListKeepsMarkers() {
        let blocks = MarkdownBlock.parse("1. first\n2. second")
        guard case let .orderedList(items) = blocks.first else {
            return XCTFail("expected ordered list, got \(blocks)")
        }
        XCTAssertEqual(items.map(\.marker), ["1", "2"])
        XCTAssertEqual(items.map(\.text), ["first", "second"])
    }

    func testBlockquoteAndRuleAndCode() {
        let blocks = MarkdownBlock.parse("> quoted\n\n---\n\n```\ncode line\n```")
        XCTAssertEqual(blocks.count, 3)
        guard case let .quote(text) = blocks[0] else {
            return XCTFail("expected quote, got \(blocks)")
        }
        XCTAssertEqual(text, "quoted")
        guard case .rule = blocks[1] else {
            return XCTFail("expected rule, got \(blocks)")
        }
        guard case let .codeBlock(code) = blocks[2] else {
            return XCTFail("expected code block, got \(blocks)")
        }
        XCTAssertEqual(code, "code line")
    }

    func testPlainParagraphPreservesText() {
        let blocks = MarkdownBlock.parse("Just a sentence with **bold**.")
        guard case let .paragraph(text) = blocks.first else {
            return XCTFail("expected paragraph, got \(blocks)")
        }
        XCTAssertEqual(text, "Just a sentence with **bold**.")
    }
}
