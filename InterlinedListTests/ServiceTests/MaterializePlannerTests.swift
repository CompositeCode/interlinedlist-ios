import XCTest
@testable import InterlinedList

/// The pure planning side of "Create from…": which columns get seeded, what the
/// titles default to, which ids go over the wire, and what the preview shows.
final class MaterializePlannerTests: XCTestCase {

    // MARK: - Fixtures

    private func message(id: String,
                         content: String = "hello",
                         username: String = "adron",
                         displayName: String? = "Adron",
                         tags: [String]? = nil) -> Message {
        Message(
            id: id, content: content, publiclyVisible: true, userId: "u1",
            createdAt: "2026-09-01T12:00:00Z", updatedAt: nil,
            user: MessageUser(id: "u1", username: username, displayName: displayName, avatar: nil),
            imageUrls: nil, videoUrls: nil, linkMetadata: nil, parentId: nil, scheduledAt: nil,
            tags: tags, digCount: nil, dugByMe: nil, crossPostUrls: nil
        )
    }

    private func prop(_ key: String,
                      _ name: String,
                      _ type: String,
                      order: Int,
                      required: Bool = false,
                      options: [String] = []) -> ListPropertyDef {
        ListPropertyDef(id: key, propertyKey: key, propertyName: name, propertyType: type,
                        displayOrder: order, isVisible: true, isRequired: required,
                        defaultValue: nil, helpText: nil, placeholder: nil,
                        selectOptions: options)
    }

    private func row(_ id: String, _ data: [String: JSONValue]) -> ListItem {
        ListItem(id: id, rowData: data, rowNumber: nil, createdAt: nil)
    }

    // MARK: - Inferred schema

    func test_inferSchema_messagesUsesTheFiveMessageColumns() {
        let fields = MaterializePlanner.inferSchema(for: .messages([message(id: "m1")]))
        XCTAssertEqual(fields.map(\.propertyKey), ["content", "author", "posted", "links", "tags"])
        XCTAssertEqual(fields.map(\.sourceKey), ["content", "author", "posted", "links", "tags"])
        XCTAssertEqual(fields[0].propertyType, "textarea")
    }

    func test_inferSchema_documentUsesSectionTextType() {
        let source = MaterializeLocalSource.document(
            MaterializeDocumentSummary(documentId: "d1", title: "Doc", content: "# A")
        )
        XCTAssertEqual(MaterializePlanner.inferSchema(for: source).map(\.propertyKey), ["section", "text", "type"])
    }

    func test_inferSchema_singleListClonesItsSchemaInDisplayOrder() {
        let list = MaterializeListSummary(
            listId: "l1", listTitle: "Books",
            fields: [prop("author", "Author", "text", order: 1), prop("title", "Title", "text", order: 0)]
        )
        let fields = MaterializePlanner.inferSchema(for: .lists([list]))
        XCTAssertEqual(fields.map(\.propertyKey), ["title", "author"], "sorted by displayOrder")
        XCTAssertEqual(fields.map(\.sourceKey), ["title", "author"], "identity mapping")
    }

    func test_inferSchema_multipleListsUsesTheSummaryColumns() {
        let source = MaterializeLocalSource.lists([
            MaterializeListSummary(listId: "l1", listTitle: "A"),
            MaterializeListSummary(listId: "l2", listTitle: "B"),
        ])
        XCTAssertEqual(MaterializePlanner.inferSchema(for: source).map(\.propertyKey),
                       ["title", "description", "rowCount", "isPublic"])
    }

    func test_inferSchema_rowsClonesTheSourceListSchema() {
        let source = MaterializeLocalSource.rows(
            listId: "l1", listTitle: "Books",
            fields: [prop("title", "Title", "text", order: 0, required: true)],
            rows: [row("r1", ["title": .string("Dune")])]
        )
        let fields = MaterializePlanner.inferSchema(for: source)
        XCTAssertEqual(fields.map(\.propertyKey), ["title"])
        XCTAssertEqual(fields[0].isRequired, true)
    }

    func test_inferSchema_keepsOptionsForASelectColumn() {
        let source = MaterializeLocalSource.rows(
            listId: "l1", listTitle: "Tasks",
            fields: [prop("state", "State", "select", order: 0, options: ["open", "closed"])],
            rows: []
        )
        let field = MaterializePlanner.inferSchema(for: source)[0]
        XCTAssertEqual(field.propertyType, "select")
        XCTAssertEqual(field.options, ["open", "closed"])
    }

    /// The server's DSL validator rejects a select/multiselect with no options.
    /// GitHub-backed lists hit this exactly — their `labels`/`assignees` columns
    /// are multiselect with none — so the seed downgrades them to text rather
    /// than building a request that is guaranteed to 400.
    func test_inferSchema_downgradesOptionlessMultiselectToText() {
        let source = MaterializeLocalSource.rows(
            listId: "l1", listTitle: "Issues",
            fields: [prop("labels", "Labels", "multiselect", order: 0)],
            rows: []
        )
        let field = MaterializePlanner.inferSchema(for: source)[0]
        XCTAssertEqual(field.propertyType, "text")
        XCTAssertNil(field.options)
    }

    // MARK: - Default titles

    func test_defaultListTitle_singleMessageNamesTheAuthor() {
        XCTAssertEqual(MaterializePlanner.defaultListTitle(for: .messages([message(id: "m1")])),
                       "Message by @adron")
    }

    func test_defaultListTitle_multipleMessagesCounts() {
        let messages = [message(id: "m1"), message(id: "m2"), message(id: "m3")]
        XCTAssertEqual(MaterializePlanner.defaultListTitle(for: .messages(messages)), "3 messages")
    }

    func test_defaultListTitle_singleListUsesItsTitle() {
        let source = MaterializeLocalSource.lists([MaterializeListSummary(listId: "l1", listTitle: "Books")])
        XCTAssertEqual(MaterializePlanner.defaultListTitle(for: source), "Books")
    }

    func test_defaultDocumentTitle_documentIsACopy() {
        let source = MaterializeLocalSource.document(
            MaterializeDocumentSummary(documentId: "d1", title: "Notes", content: "")
        )
        XCTAssertEqual(MaterializePlanner.defaultDocumentTitle(for: source), "Copy of Notes")
    }

    func test_defaultDocumentTitle_singleMessageUsesItsFirstNonEmptyLine() {
        let source = MaterializeLocalSource.messages([message(id: "m1", content: "\n\nTacos in Seattle\nmore text")])
        XCTAssertEqual(MaterializePlanner.defaultDocumentTitle(for: source), "Tacos in Seattle")
    }

    func test_defaultDocumentTitle_emptyMessageFallsBackToTheAuthor() {
        let source = MaterializeLocalSource.messages([message(id: "m1", content: "   ")])
        XCTAssertEqual(MaterializePlanner.defaultDocumentTitle(for: source), "Message by @adron")
    }

    // MARK: - Source references (ids only)

    func test_sourceRef_messagesCarriesOnlyIds() {
        let ref = MaterializePlanner.sourceRef(for: .messages([message(id: "m1"), message(id: "m2")]))
        XCTAssertEqual(ref, .messages(messageIds: ["m1", "m2"]))
    }

    func test_sourceRef_rowsCarriesListIdAndRowIds() {
        let source = MaterializeLocalSource.rows(
            listId: "l1", listTitle: "Books", fields: [],
            rows: [row("r1", [:]), row("r2", [:])]
        )
        XCTAssertEqual(MaterializePlanner.sourceRef(for: source), .rows(listId: "l1", rowIds: ["r1", "r2"]))
    }

    func test_sourceRef_documentCarriesDocumentId() {
        let source = MaterializeLocalSource.document(
            MaterializeDocumentSummary(documentId: "d1", title: "Doc", content: "")
        )
        XCTAssertEqual(MaterializePlanner.sourceRef(for: source), .document(documentId: "d1"))
    }

    // MARK: - Preview projection

    func test_previewRows_messageColumnsProjectTheExpectedValues() {
        let source = MaterializeLocalSource.messages([
            message(id: "m1", content: "Tacos", tags: ["food", "seattle"])
        ])
        let fields = MaterializePlanner.inferSchema(for: source)
        let rows = MaterializePlanner.previewRows(for: source, fields: fields)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0]["content"], "Tacos")
        XCTAssertEqual(rows[0]["author"], "Adron (@adron)")
        XCTAssertEqual(rows[0]["tags"], "food, seattle")
    }

    func test_previewRows_authorFallsBackToHandleWhenThereIsNoDisplayName() {
        let source = MaterializeLocalSource.messages([message(id: "m1", displayName: nil)])
        let fields = MaterializePlanner.inferSchema(for: source)
        XCTAssertEqual(MaterializePlanner.previewRows(for: source, fields: fields)[0]["author"], "@adron")
    }

    /// A user-added column has no `sourceKey`, so the server fills it with "" —
    /// the preview must say the same thing rather than inventing a value.
    func test_previewRows_userAddedColumnIsEmpty() {
        let source = MaterializeLocalSource.messages([message(id: "m1", content: "Tacos")])
        let fields = [
            MaterializeFieldConfig(propertyKey: "content", propertyName: "Content", propertyType: "text", sourceKey: "content"),
            MaterializeFieldConfig(propertyKey: "notes", propertyName: "Notes", propertyType: "text", sourceKey: nil),
        ]
        let rows = MaterializePlanner.previewRows(for: source, fields: fields)
        XCTAssertEqual(rows[0]["content"], "Tacos")
        XCTAssertEqual(rows[0]["notes"], "")
    }

    func test_previewRows_rowsReadThroughTheColumnSourceKey() {
        let source = MaterializeLocalSource.rows(
            listId: "l1", listTitle: "Books",
            fields: [prop("title", "Title", "text", order: 0)],
            rows: [row("r1", ["title": .string("Dune")]), row("r2", ["title": .string("Neuromancer")])]
        )
        let fields = MaterializePlanner.inferSchema(for: source)
        XCTAssertEqual(MaterializePlanner.previewRows(for: source, fields: fields).map { $0["title"] },
                       ["Dune", "Neuromancer"])
    }

    func test_previewRows_multipleListsSummarizeOnePerRow() {
        let source = MaterializeLocalSource.lists([
            MaterializeListSummary(listId: "l1", listTitle: "Books", description: "to read", isPublic: true,
                                   rows: [row("r1", [:]), row("r2", [:])]),
            MaterializeListSummary(listId: "l2", listTitle: "Films"),
        ])
        let fields = MaterializePlanner.inferSchema(for: source)
        let rows = MaterializePlanner.previewRows(for: source, fields: fields)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0]["title"], "Books")
        XCTAssertEqual(rows[0]["description"], "to read")
        XCTAssertEqual(rows[0]["rowCount"], "2")
        XCTAssertEqual(rows[0]["isPublic"], "true")
        XCTAssertEqual(rows[1]["isPublic"], "false")
    }

    func test_previewRows_documentTurnsHeadingsAndItemsIntoRows() {
        let source = MaterializeLocalSource.document(MaterializeDocumentSummary(
            documentId: "d1", title: "Reading", content: "# Books\n\n- Dune\n- Neuromancer"
        ))
        let fields = MaterializePlanner.inferSchema(for: source)
        let rows = MaterializePlanner.previewRows(for: source, fields: fields)
        XCTAssertEqual(rows.map { $0["text"] }, ["Books", "Dune", "Neuromancer"])
        XCTAssertEqual(rows[1]["section"], "Books")
        XCTAssertEqual(rows[1]["type"], "list-item")
    }

    func test_previewRows_respectsTheLimit() {
        let messages = (1...40).map { message(id: "m\($0)") }
        let source = MaterializeLocalSource.messages(messages)
        let fields = MaterializePlanner.inferSchema(for: source)
        XCTAssertEqual(MaterializePlanner.previewRows(for: source, fields: fields, limit: 5).count, 5)
    }
}
