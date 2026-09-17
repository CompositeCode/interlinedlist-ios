import XCTest
@testable import InterlinedList

final class ListRowSortingTests: XCTestCase {

    private func field(
        _ key: String, _ name: String, order: Int,
        type: String = "text", visible: Bool = true
    ) -> ListPropertyDef {
        ListPropertyDef(
            id: key, propertyKey: key, propertyName: name, propertyType: type,
            displayOrder: order, isVisible: visible, isRequired: false,
            defaultValue: nil, helpText: nil, placeholder: nil,
            isReadOnly: false, selectOptions: []
        )
    }

    private func row(_ id: String, _ data: [String: JSONValue]) -> ListItem {
        ListItem(id: id, rowData: data, rowNumber: nil, createdAt: nil)
    }

    private var schema: [ListPropertyDef] {
        [
            field("title", "Title", order: 0),
            field("score", "Score", order: 1, type: "number"),
            field("done", "Done", order: 2, type: "boolean"),
            field("due", "Due", order: 3, type: "date"),
            field("status", "Status", order: 4, type: "select"),
            field("secret", "Secret", order: 5, visible: false),
        ]
    }

    // MARK: Search

    func test_search_matchesAcrossVisibleValues_caseInsensitively() {
        let items = [
            row("1", ["title": .string("Alpha"), "status": .string("open")]),
            row("2", ["title": .string("Beta"), "status": .string("closed")]),
        ]
        XCTAssertEqual(ListRowSorting.search(items, query: "alp", schema: schema).map(\.id), ["1"])
        XCTAssertEqual(ListRowSorting.search(items, query: "CLOSED", schema: schema).map(\.id), ["2"])
    }

    func test_search_ignoresHiddenColumns() {
        let items = [row("1", ["title": .string("Alpha"), "secret": .string("needle")])]
        XCTAssertTrue(
            ListRowSorting.search(items, query: "needle", schema: schema).isEmpty,
            "Search must not match a column the user cannot see"
        )
    }

    func test_search_emptyOrWhitespaceQueryReturnsEverything() {
        let items = [row("1", ["title": .string("A")]), row("2", ["title": .string("B")])]
        XCTAssertEqual(ListRowSorting.search(items, query: "", schema: schema).count, 2)
        XCTAssertEqual(ListRowSorting.search(items, query: "   ", schema: schema).count, 2)
    }

    // MARK: Filter

    func test_filter_matchesExactValue() {
        let items = [
            row("1", ["status": .string("open")]),
            row("2", ["status": .string("closed")]),
            row("3", ["status": .string("open")]),
        ]
        let filtered = ListRowSorting.filter(items, by: ListValueFilter(propertyKey: "status", value: "open"))
        XCTAssertEqual(filtered.map(\.id), ["1", "3"])
    }

    func test_filter_nilReturnsEverything() {
        let items = [row("1", ["status": .string("open")])]
        XCTAssertEqual(ListRowSorting.filter(items, by: nil).count, 1)
    }

    func test_distinctValues_areUniqueSortedAndSkipBlanks() {
        let items = [
            row("1", ["status": .string("open")]),
            row("2", ["status": .string("closed")]),
            row("3", ["status": .string("open")]),
            row("4", ["status": .string("")]),
            row("5", [:]),
        ]
        XCTAssertEqual(ListRowSorting.distinctValues(of: "status", in: items), ["closed", "open"])
    }

    func test_filterableProperties_areEnumeratedOrBooleanOnly() {
        let keys = ListRowSorting.filterableProperties(in: schema).map(\.propertyKey)
        XCTAssertEqual(keys, ["done", "status"])
        XCTAssertFalse(keys.contains("secret"), "Hidden properties are not offered")
    }

    // MARK: Sort — per type

    func test_sort_numbersCompareNumerically_notAsText() {
        let items = [
            row("a", ["score": .number(9)]),
            row("b", ["score": .number(10)]),
            row("c", ["score": .number(1)]),
        ]
        let order = ListSortOrder(propertyKey: "score", direction: .ascending)
        XCTAssertEqual(ListRowSorting.sort(items, by: order, schema: schema).map(\.id), ["c", "a", "b"])
    }

    func test_sort_booleansFalseBeforeTrueAscending() {
        let items = [
            row("a", ["done": .bool(true)]),
            row("b", ["done": .bool(false)]),
        ]
        let order = ListSortOrder(propertyKey: "done", direction: .ascending)
        XCTAssertEqual(ListRowSorting.sort(items, by: order, schema: schema).map(\.id), ["b", "a"])
    }

    func test_sort_datesCompareChronologically() {
        let items = [
            row("a", ["due": .string("2026-09-15T10:00:00.000Z")]),
            row("b", ["due": .string("2026-01-02T10:00:00.000Z")]),
            row("c", ["due": .string("2026-12-31T10:00:00.000Z")]),
        ]
        let order = ListSortOrder(propertyKey: "due", direction: .ascending)
        XCTAssertEqual(ListRowSorting.sort(items, by: order, schema: schema).map(\.id), ["b", "a", "c"])
    }

    func test_sort_textIsNumericAware() {
        let items = [
            row("a", ["title": .string("Item 10")]),
            row("b", ["title": .string("Item 9")]),
        ]
        let order = ListSortOrder(propertyKey: "title", direction: .ascending)
        XCTAssertEqual(
            ListRowSorting.sort(items, by: order, schema: schema).map(\.id), ["b", "a"],
            "\"Item 9\" must sort before \"Item 10\""
        )
    }

    func test_sort_descendingReversesOrder() {
        let items = [
            row("a", ["score": .number(1)]),
            row("b", ["score": .number(2)]),
        ]
        let order = ListSortOrder(propertyKey: "score", direction: .descending)
        XCTAssertEqual(ListRowSorting.sort(items, by: order, schema: schema).map(\.id), ["b", "a"])
    }

    // MARK: Sort — blanks and stability

    func test_sort_blankValuesSinkToTheBottomInBothDirections() {
        let items = [
            row("a", ["score": .number(2)]),
            row("blank", [:]),
            row("b", ["score": .number(1)]),
        ]
        let asc = ListSortOrder(propertyKey: "score", direction: .ascending)
        let desc = ListSortOrder(propertyKey: "score", direction: .descending)
        XCTAssertEqual(ListRowSorting.sort(items, by: asc, schema: schema).map(\.id), ["b", "a", "blank"])
        XCTAssertEqual(
            ListRowSorting.sort(items, by: desc, schema: schema).map(\.id), ["a", "b", "blank"],
            "An empty cell is unknown, not smallest — flipping direction must not float blanks up"
        )
    }

    func test_sort_isStableForEqualValues() {
        let items = [
            row("first", ["score": .number(1)]),
            row("second", ["score": .number(1)]),
            row("third", ["score": .number(1)]),
        ]
        let order = ListSortOrder(propertyKey: "score", direction: .ascending)
        XCTAssertEqual(
            ListRowSorting.sort(items, by: order, schema: schema).map(\.id),
            ["first", "second", "third"]
        )
    }

    func test_sort_nilOrderOrUnknownKeyKeepsServerOrder() {
        let items = [row("a", ["score": .number(9)]), row("b", ["score": .number(1)])]
        XCTAssertEqual(ListRowSorting.sort(items, by: nil, schema: schema).map(\.id), ["a", "b"])
        let unknown = ListSortOrder(propertyKey: "nope", direction: .ascending)
        XCTAssertEqual(ListRowSorting.sort(items, by: unknown, schema: schema).map(\.id), ["a", "b"])
    }

    // MARK: Composition with the GitHub state filter

    func test_searchFilterAndSortCompose() {
        // Mirrors the view's pipeline over rows the GitHub open/closed filter already kept.
        let openRows = [
            row("1", ["title": .string("fix login"), "status": .string("bug"), "score": .number(3)]),
            row("2", ["title": .string("fix logout"), "status": .string("bug"), "score": .number(1)]),
            row("3", ["title": .string("fix login"), "status": .string("chore"), "score": .number(2)]),
        ]
        let searched = ListRowSorting.search(openRows, query: "fix log", schema: schema)
        let filtered = ListRowSorting.filter(searched, by: ListValueFilter(propertyKey: "status", value: "bug"))
        let sorted = ListRowSorting.sort(
            filtered, by: ListSortOrder(propertyKey: "score", direction: .ascending), schema: schema
        )
        XCTAssertEqual(sorted.map(\.id), ["2", "1"])
    }

    // MARK: Scale

    func test_sort_handlesFiveHundredRows() {
        let items = (0..<500).map { row("r\($0)", ["score": .number(Double(500 - $0))]) }
        let order = ListSortOrder(propertyKey: "score", direction: .ascending)
        let sorted = ListRowSorting.sort(items, by: order, schema: schema)
        XCTAssertEqual(sorted.count, 500)
        XCTAssertEqual(sorted.first?.id, "r499")
        XCTAssertEqual(sorted.last?.id, "r0")
    }
}
