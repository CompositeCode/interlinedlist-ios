import XCTest
@testable import InterlinedList

/// `MarkdownBlocks` is a port of the backend's `lib/materialize/markdown-blocks.ts`.
/// These cases mirror its behavior — if the two ever diverge, the "Create from a
/// document" preview stops matching what the server actually builds.
final class MarkdownBlocksTests: XCTestCase {

    func test_split_emptyStringProducesNoBlocks() {
        XCTAssertTrue(MarkdownBlocks.split("").isEmpty)
    }

    func test_split_headingCapturesLevelAndText() {
        let blocks = MarkdownBlocks.split("### Chapter One")
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].type, .heading)
        XCTAssertEqual(blocks[0].level, 3)
        XCTAssertEqual(blocks[0].text, "Chapter One")
        XCTAssertEqual(blocks[0].section, "Chapter One", "a heading is its own section")
    }

    func test_split_hashWithoutSpaceIsNotAHeading() {
        let blocks = MarkdownBlocks.split("#hashtag not a heading")
        XCTAssertEqual(blocks[0].type, .paragraph)
    }

    func test_split_sevenHashesIsNotAHeading() {
        let blocks = MarkdownBlocks.split("####### too deep")
        XCTAssertEqual(blocks[0].type, .paragraph)
    }

    func test_split_blocksInheritTheNearestPrecedingHeading() throws {
        let blocks = MarkdownBlocks.split("Intro line\n\n# Books\n\n- Dune\n\n## Later\n\n- Snow Crash")
        let dune = try XCTUnwrap(blocks.first { $0.text == "Dune" })
        let snowCrash = try XCTUnwrap(blocks.first { $0.text == "Snow Crash" })
        XCTAssertEqual(blocks[0].section, "", "text before any heading has no section")
        XCTAssertEqual(dune.section, "Books")
        XCTAssertEqual(snowCrash.section, "Later")
    }

    func test_split_unorderedListMarkers() {
        for marker in ["-", "*", "+"] {
            let blocks = MarkdownBlocks.split("\(marker) item")
            XCTAssertEqual(blocks.first?.type, .listItem, "marker \(marker)")
            XCTAssertEqual(blocks.first?.text, "item")
        }
    }

    func test_split_orderedListMarkers() {
        for marker in ["1.", "2)"] {
            let blocks = MarkdownBlocks.split("\(marker) item")
            XCTAssertEqual(blocks.first?.type, .listItem, "marker \(marker)")
            XCTAssertEqual(blocks.first?.text, "item")
        }
    }

    func test_split_listItemNestingLevelFromIndent() {
        let blocks = MarkdownBlocks.split("- top\n  - nested\n    - deeper")
        XCTAssertEqual(blocks.map(\.level), [1, 2, 3])
    }

    func test_split_tabIndentCountsAsTwoSpaces() {
        let blocks = MarkdownBlocks.split("- top\n\t- nested")
        XCTAssertEqual(blocks.map(\.level), [1, 2])
    }

    func test_split_consecutiveLinesJoinIntoOneParagraph() {
        let blocks = MarkdownBlocks.split("first line\nsecond line\n\nnew paragraph")
        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(blocks[0].text, "first line second line")
        XCTAssertEqual(blocks[1].text, "new paragraph")
    }

    func test_split_fencedCodeIsOneBlockAndKeepsItsLines() throws {
        let blocks = MarkdownBlocks.split("before\n\n```swift\nlet a = 1\nlet b = 2\n```\n\nafter")
        let code = try XCTUnwrap(blocks.first { $0.type == .code })
        XCTAssertEqual(code.text, "let a = 1\nlet b = 2")
        XCTAssertEqual(blocks.last?.text, "after", "content after the closing fence still parses")
    }

    func test_split_tildeFenceAlsoWorks() {
        let blocks = MarkdownBlocks.split("~~~\nraw\n~~~")
        XCTAssertEqual(blocks.first?.type, .code)
        XCTAssertEqual(blocks.first?.text, "raw")
    }

    func test_split_unterminatedFenceConsumesToEnd() {
        let blocks = MarkdownBlocks.split("```\nnever closed\nstill code")
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].type, .code)
        XCTAssertEqual(blocks[0].text, "never closed\nstill code")
    }

    func test_split_blockquoteStripsMarker() {
        let blocks = MarkdownBlocks.split("> quoted text")
        XCTAssertEqual(blocks.first?.type, .quote)
        XCTAssertEqual(blocks.first?.text, "quoted text")
    }

    func test_split_crlfNormalizes() {
        let blocks = MarkdownBlocks.split("# Title\r\n\r\n- one")
        XCTAssertEqual(blocks.map(\.type), [.heading, .listItem])
        XCTAssertEqual(blocks[1].text, "one")
    }

    // MARK: - rowBlocks

    func test_rowBlocks_prefersHeadingsAndListItems() {
        let blocks = MarkdownBlocks.rowBlocks("# Books\n\nsome prose\n\n- Dune\n- Neuromancer")
        XCTAssertEqual(blocks.map(\.text), ["Books", "Dune", "Neuromancer"])
        XCTAssertFalse(blocks.contains { $0.text == "some prose" })
    }

    func test_rowBlocks_fallsBackToEveryBlockWhenThereAreNoHeadingsOrItems() {
        let blocks = MarkdownBlocks.rowBlocks("just a paragraph\n\nand another")
        XCTAssertEqual(blocks.map(\.text), ["just a paragraph", "and another"])
    }

    func test_rowBlocks_emptyDocumentProducesNoRows() {
        XCTAssertTrue(MarkdownBlocks.rowBlocks("   \n\n  ").isEmpty)
    }
}
