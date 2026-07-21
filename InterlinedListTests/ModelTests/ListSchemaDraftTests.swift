import XCTest
@testable import InterlinedList

final class ListSchemaDraftTests: XCTestCase {

    private func makeProp(
        id: String = UUID().uuidString,
        name: String = "Title",
        type: String = "text",
        isVisible: Bool = true,
        isRequired: Bool = false,
        key: String = "title"
    ) -> DraftProperty {
        DraftProperty(
            id: id,
            propertyKey: key,
            propertyName: name,
            propertyType: type,
            isVisible: isVisible,
            isRequired: isRequired
        )
    }

    // MARK: isTitleValid

    func test_isTitleValid_emptyString_fails() {
        XCTAssertFalse(ListSchemaDraft.isTitleValid(""))
    }

    func test_isTitleValid_whitespaceOnly_fails() {
        XCTAssertFalse(ListSchemaDraft.isTitleValid("   \n  "))
    }

    func test_isTitleValid_singleCharacter_passes() {
        XCTAssertTrue(ListSchemaDraft.isTitleValid("A"))
    }

    func test_isTitleValid_120Characters_passes() {
        let s = String(repeating: "x", count: 120)
        XCTAssertTrue(ListSchemaDraft.isTitleValid(s))
    }

    func test_isTitleValid_121Characters_fails() {
        let s = String(repeating: "x", count: 121)
        XCTAssertFalse(ListSchemaDraft.isTitleValid(s))
    }

    // MARK: metadataChanged

    func test_metadataChanged_noChange_returnsFalse() {
        let changed = ListSchemaDraft.metadataChanged(
            originalTitle: "T", originalDescription: "D", originalIsPublic: false,
            title: "T", description: "D", isPublic: false
        )
        XCTAssertFalse(changed)
    }

    func test_metadataChanged_titleFlipped_returnsTrue() {
        let changed = ListSchemaDraft.metadataChanged(
            originalTitle: "T", originalDescription: "D", originalIsPublic: false,
            title: "T2", description: "D", isPublic: false
        )
        XCTAssertTrue(changed)
    }

    func test_metadataChanged_descriptionFlipped_returnsTrue() {
        let changed = ListSchemaDraft.metadataChanged(
            originalTitle: "T", originalDescription: "D", originalIsPublic: false,
            title: "T", description: "D2", isPublic: false
        )
        XCTAssertTrue(changed)
    }

    func test_metadataChanged_isPublicFlipped_returnsTrue() {
        let changed = ListSchemaDraft.metadataChanged(
            originalTitle: "T", originalDescription: "D", originalIsPublic: false,
            title: "T", description: "D", isPublic: true
        )
        XCTAssertTrue(changed)
    }

    func test_metadataChanged_whitespaceOnlyAroundOriginal_treatedAsNoChange() {
        let changed = ListSchemaDraft.metadataChanged(
            originalTitle: "T", originalDescription: "D", originalIsPublic: false,
            title: "  T  ", description: "  D  ", isPublic: false
        )
        XCTAssertFalse(changed)
    }

    // MARK: schemaChanged

    func test_schemaChanged_identical_returnsFalse() {
        let p = makeProp(id: "1")
        XCTAssertFalse(ListSchemaDraft.schemaChanged(original: [p], current: [p]))
    }

    func test_schemaChanged_add_returnsTrue() {
        let a = makeProp(id: "1", name: "A")
        let b = makeProp(id: "2", name: "B")
        XCTAssertTrue(ListSchemaDraft.schemaChanged(original: [a], current: [a, b]))
    }

    func test_schemaChanged_delete_returnsTrue() {
        let a = makeProp(id: "1", name: "A")
        let b = makeProp(id: "2", name: "B")
        XCTAssertTrue(ListSchemaDraft.schemaChanged(original: [a, b], current: [a]))
    }

    func test_schemaChanged_reorder_returnsTrue() {
        let a = makeProp(id: "1", name: "A")
        let b = makeProp(id: "2", name: "B")
        XCTAssertTrue(ListSchemaDraft.schemaChanged(original: [a, b], current: [b, a]))
    }

    func test_schemaChanged_rename_returnsTrue() {
        let original = makeProp(id: "1", name: "Old")
        var renamed = original
        renamed.propertyName = "New"
        XCTAssertTrue(ListSchemaDraft.schemaChanged(original: [original], current: [renamed]))
    }

    func test_schemaChanged_typeChange_returnsTrue() {
        let original = makeProp(id: "1", type: "text")
        var changed = original
        changed.propertyType = "number"
        XCTAssertTrue(ListSchemaDraft.schemaChanged(original: [original], current: [changed]))
    }

    func test_schemaChanged_visibilityFlip_returnsTrue() {
        let original = makeProp(id: "1", isVisible: true)
        var changed = original
        changed.isVisible = false
        XCTAssertTrue(ListSchemaDraft.schemaChanged(original: [original], current: [changed]))
    }

    func test_schemaChanged_requiredFlip_returnsTrue() {
        let original = makeProp(id: "1", isRequired: false)
        var changed = original
        changed.isRequired = true
        XCTAssertTrue(ListSchemaDraft.schemaChanged(original: [original], current: [changed]))
    }

    // MARK: serializeSchemaDSL

    func test_serializeSchemaDSL_empty_returnsEmptyString() {
        XCTAssertEqual(ListSchemaDraft.serializeSchemaDSL([]), "")
    }

    func test_serializeSchemaDSL_onePropertyTextType_returnsNameColonType() {
        let p = makeProp(name: "Name", type: "text")
        XCTAssertEqual(ListSchemaDraft.serializeSchemaDSL([p]), "Name:text")
    }

    func test_serializeSchemaDSL_multipleProperties_returnsCommaSpaceSeparated() {
        let a = makeProp(id: "1", name: "Title", type: "text")
        let b = makeProp(id: "2", name: "Year", type: "number")
        let c = makeProp(id: "3", name: "Read", type: "boolean")
        XCTAssertEqual(ListSchemaDraft.serializeSchemaDSL([a, b, c]),
                       "Title:text, Year:number, Read:boolean")
    }

    func test_serializeSchemaDSL_excludesEmptyNames() {
        let a = makeProp(id: "1", name: "Title", type: "text")
        let blank = makeProp(id: "2", name: "  ", type: "text")
        let c = makeProp(id: "3", name: "", type: "number")
        let d = makeProp(id: "4", name: "Year", type: "number")
        XCTAssertEqual(ListSchemaDraft.serializeSchemaDSL([a, blank, c, d]),
                       "Title:text, Year:number")
    }

    func test_serializeSchemaDSL_trimsWhitespaceAroundName() {
        let p = makeProp(name: "  Title  ", type: "text")
        XCTAssertEqual(ListSchemaDraft.serializeSchemaDSL([p]), "Title:text")
    }

    // MARK: isSchemaValid

    func test_isSchemaValid_empty_accepts() {
        XCTAssertTrue(ListSchemaDraft.isSchemaValid([]))
    }

    func test_isSchemaValid_healthyMix_accepts() {
        let props = [
            makeProp(id: "1", name: "Title", type: "text"),
            makeProp(id: "2", name: "Year", type: "number"),
            makeProp(id: "3", name: "Read", type: "boolean"),
            makeProp(id: "4", name: "Added", type: "date"),
            makeProp(id: "5", name: "Site", type: "url"),
            makeProp(id: "6", name: "Author", type: "email"),
        ]
        XCTAssertTrue(ListSchemaDraft.isSchemaValid(props))
    }

    func test_isSchemaValid_emptyName_rejects() {
        let props = [
            makeProp(id: "1", name: "Title", type: "text"),
            makeProp(id: "2", name: "", type: "text"),
        ]
        XCTAssertFalse(ListSchemaDraft.isSchemaValid(props))
    }

    func test_isSchemaValid_whitespaceOnlyName_rejects() {
        let props = [makeProp(id: "1", name: "  \t ", type: "text")]
        XCTAssertFalse(ListSchemaDraft.isSchemaValid(props))
    }

    func test_isSchemaValid_unsupportedType_rejects() {
        let props = [makeProp(id: "1", name: "Title", type: "unsupported")]
        XCTAssertFalse(ListSchemaDraft.isSchemaValid(props))
    }

    // MARK: starterColumns

    func test_starterColumns_returnsSingleTitleTextColumn() {
        let cols = ListSchemaDraft.starterColumns()
        XCTAssertEqual(cols.count, 1)
        XCTAssertEqual(cols.first?.propertyName, "Title")
        XCTAssertEqual(cols.first?.propertyType, "text")
    }

    func test_starterColumns_serializeToValidDSL() {
        let dsl = ListSchemaDraft.serializeSchemaDSL(ListSchemaDraft.starterColumns())
        XCTAssertEqual(dsl, "Title:text")
    }

    // MARK: hasCreatableColumns

    func test_hasCreatableColumns_empty_rejects() {
        XCTAssertFalse(ListSchemaDraft.hasCreatableColumns([]))
    }

    func test_hasCreatableColumns_starterColumns_accepts() {
        XCTAssertTrue(ListSchemaDraft.hasCreatableColumns(ListSchemaDraft.starterColumns()))
    }

    func test_hasCreatableColumns_anyBlankName_rejects() {
        let props = [
            makeProp(id: "1", name: "Title", type: "text"),
            makeProp(id: "2", name: "  ", type: "text"),
        ]
        XCTAssertFalse(ListSchemaDraft.hasCreatableColumns(props))
    }

    func test_hasCreatableColumns_unsupportedType_rejects() {
        let props = [makeProp(id: "1", name: "Title", type: "bogus")]
        XCTAssertFalse(ListSchemaDraft.hasCreatableColumns(props))
    }
}
