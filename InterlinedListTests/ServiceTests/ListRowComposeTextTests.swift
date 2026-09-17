import XCTest
@testable import InterlinedList

final class ListRowComposeTextTests: XCTestCase {

    private func field(
        _ key: String,
        _ name: String,
        order: Int,
        type: String = "text",
        visible: Bool = true,
        readOnly: Bool = false
    ) -> ListPropertyDef {
        ListPropertyDef(
            id: key,
            propertyKey: key,
            propertyName: name,
            propertyType: type,
            displayOrder: order,
            isVisible: visible,
            isRequired: false,
            defaultValue: nil,
            helpText: nil,
            placeholder: nil,
            isReadOnly: readOnly,
            selectOptions: []
        )
    }

    /// A schema whose first field is an id — the case `schema.first` gets wrong.
    private var schema: [ListPropertyDef] {
        [
            field("number", "Number", order: 0, type: "number", readOnly: true),
            field("title", "Title", order: 1),
            field("status", "Status", order: 2, type: "select"),
            field("notes", "Notes", order: 3, type: "textarea"),
            field("internal", "Internal", order: 4, visible: false),
        ]
    }

    func test_headlineComesFromPrimaryDisplayField_notTheFirstColumn() {
        let row: [String: JSONValue] = [
            "number": .number(42),
            "title": .string("Ship the thing"),
            "status": .string("open"),
        ]
        let body = ListRowComposeText.body(listTitle: "Roadmap", schema: schema, row: row)
        let lines = body.components(separatedBy: "\n\n")
        XCTAssertEqual(lines.first, "Roadmap")
        XCTAssertEqual(lines[1], "Ship the thing", "Headline must be the primary display field, not the id column")
        XCTAssertFalse(body.hasPrefix("42"))
    }

    func test_remainingVisibleFieldsFollowAsLabelledLines() {
        let row: [String: JSONValue] = [
            "number": .number(42),
            "title": .string("Ship the thing"),
            "status": .string("open"),
            "notes": .string("Blocked on review"),
        ]
        let body = ListRowComposeText.body(listTitle: "Roadmap", schema: schema, row: row)
        XCTAssertTrue(body.contains("Status: open"), body)
        XCTAssertTrue(body.contains("Notes: Blocked on review"), body)
        XCTAssertTrue(body.contains("Number: 42"), "A visible read-only column is still context worth carrying")
    }

    func test_headlineIsNotRepeatedInTheDetailLines() {
        let row: [String: JSONValue] = ["title": .string("Ship the thing"), "status": .string("open")]
        let body = ListRowComposeText.body(listTitle: "Roadmap", schema: schema, row: row)
        let occurrences = body.components(separatedBy: "Ship the thing").count - 1
        XCTAssertEqual(occurrences, 1)
        XCTAssertFalse(body.contains("Title: Ship the thing"))
    }

    func test_hiddenFieldsAreExcluded() {
        let row: [String: JSONValue] = ["title": .string("T"), "internal": .string("secret")]
        let body = ListRowComposeText.body(listTitle: "Roadmap", schema: schema, row: row)
        XCTAssertFalse(body.contains("secret"))
        XCTAssertFalse(body.contains("Internal"))
    }

    func test_emptyAndMissingCellsProduceNoLabelNoise() {
        let row: [String: JSONValue] = ["title": .string("T"), "status": .string("   "), "number": .null]
        let body = ListRowComposeText.body(listTitle: "Roadmap", schema: schema, row: row)
        XCTAssertFalse(body.contains("Status:"), "An empty cell must not become a label the user has to delete")
        XCTAssertFalse(body.contains("Notes:"), "A missing cell must not appear at all")
        XCTAssertFalse(body.contains("Number:"), "A null cell renders as empty and must be dropped too")
    }

    func test_emptyListTitleIsOmittedRatherThanLeavingABlankLine() {
        let row: [String: JSONValue] = ["title": .string("Ship the thing")]
        let body = ListRowComposeText.body(listTitle: "   ", schema: schema, row: row)
        XCTAssertEqual(body, "Ship the thing")
    }

    func test_emptyRowYieldsJustTheListTitle() {
        let body = ListRowComposeText.body(listTitle: "Roadmap", schema: schema, row: [:])
        XCTAssertEqual(body, "Roadmap")
    }
}
