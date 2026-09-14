import XCTest
@testable import InterlinedList

/// The editor-to-wire mapping for a "Create from…" column.
final class CreateFromColumnTests: XCTestCase {

    func test_sourceMappedColumn_keepsItsOriginalKeyThroughARename() {
        var column = CreateFromColumn(from: MaterializeFieldConfig(
            propertyKey: "content", propertyName: "Content", propertyType: "textarea", sourceKey: "content"
        ))
        column.name = "The Post"
        let config = column.config(fallbackIndex: 0)
        XCTAssertEqual(config.propertyKey, "content", "renaming must not break the source mapping")
        XCTAssertEqual(config.propertyName, "The Post")
        XCTAssertEqual(config.sourceKey, "content")
    }

    func test_userAddedColumn_derivesItsKeyFromTheName() {
        let column = CreateFromColumn(name: "My Notes")
        XCTAssertEqual(column.config(fallbackIndex: 0).propertyKey, "my_notes")
    }

    func test_userAddedColumn_hasNoSourceKey() {
        XCTAssertNil(CreateFromColumn(name: "Notes").config(fallbackIndex: 0).sourceKey)
    }

    func test_userAddedColumn_unnamedFallsBackToAPositionalKey() {
        XCTAssertEqual(CreateFromColumn(name: "").config(fallbackIndex: 2).propertyKey, "column_3")
    }

    func test_config_trimsTheDisplayName() {
        let column = CreateFromColumn(name: "  Padded  ")
        XCTAssertEqual(column.config(fallbackIndex: 0).propertyName, "Padded")
    }

    func test_slug_collapsesPunctuationAndSpaces() {
        XCTAssertEqual(CreateFromColumn.slug("Due  Date!!", fallback: "x"), "due_date")
        XCTAssertEqual(CreateFromColumn.slug("a/b-c", fallback: "x"), "a_b_c")
    }

    func test_slug_stripsTrailingSeparators() {
        XCTAssertEqual(CreateFromColumn.slug("Name…", fallback: "x"), "name")
    }

    func test_slug_allPunctuationFallsBack() {
        XCTAssertEqual(CreateFromColumn.slug("!!!", fallback: "column_1"), "column_1")
    }

    func test_supportedTypes_excludeSelectAndMultiselect() {
        // Both require an `options` array the editor has no way to collect, and
        // the server's DSL validator rejects them without one.
        XCTAssertFalse(MaterializeFieldConfig.supportedTypes.contains("select"))
        XCTAssertFalse(MaterializeFieldConfig.supportedTypes.contains("multiselect"))
        XCTAssertTrue(MaterializeFieldConfig.supportedTypes.contains("textarea"))
    }

    func test_targetFlags() {
        XCTAssertTrue(MaterializeTarget.list.createsList)
        XCTAssertFalse(MaterializeTarget.list.createsDocument)
        XCTAssertFalse(MaterializeTarget.doc.createsList)
        XCTAssertTrue(MaterializeTarget.doc.createsDocument)
        XCTAssertTrue(MaterializeTarget.both.createsList)
        XCTAssertTrue(MaterializeTarget.both.createsDocument)
    }
}
