//
//  MaterializePlanner.swift
//  InterlinedList
//

import Foundation

/// One source list, hydrated with its schema and rows, for a `lists` source.
struct MaterializeListSummary {
    let listId: String
    let listTitle: String
    let description: String?
    let isPublic: Bool
    let fields: [ListPropertyDef]
    let rows: [ListItem]
    let totalRows: Int

    init(listId: String,
         listTitle: String,
         description: String? = nil,
         isPublic: Bool = false,
         fields: [ListPropertyDef] = [],
         rows: [ListItem] = [],
         totalRows: Int? = nil) {
        self.listId = listId
        self.listTitle = listTitle
        self.description = description
        self.isPublic = isPublic
        self.fields = fields
        self.rows = rows
        self.totalRows = totalRows ?? rows.count
    }
}

struct MaterializeDocumentSummary {
    let documentId: String
    let title: String
    let content: String
}

/// An in-memory source for the "Create from…" preview. The wire request carries
/// only the ids from `sourceRef`; these full objects exist solely so the sheet
/// can seed its column editor and render a preview.
enum MaterializeLocalSource {
    case messages([Message])
    case lists([MaterializeListSummary])
    case rows(listId: String, listTitle: String, fields: [ListPropertyDef], rows: [ListItem])
    case document(MaterializeDocumentSummary)
}

/// Pure planning for "Create from…": the default columns, the default titles,
/// and the preview rows. Ported from the backend's `lib/materialize/build-list.ts`
/// so the sheet shows what the server will build.
///
/// The server is authoritative — it re-derives every cell from re-fetched data
/// via each column's `sourceKey`. Divergence here only affects the preview.
enum MaterializePlanner {

    // MARK: - Default schemas

    private static func field(_ key: String, _ name: String, _ type: String, _ sourceKey: String?) -> MaterializeFieldConfig {
        MaterializeFieldConfig(propertyKey: key, propertyName: name, propertyType: type, sourceKey: sourceKey)
    }

    private static var messageFields: [MaterializeFieldConfig] {
        [
            field("content", "Content", "textarea", "content"),
            field("author", "Author", "text", "author"),
            field("posted", "Posted", "text", "posted"),
            field("links", "Links", "textarea", "links"),
            field("tags", "Tags", "text", "tags"),
        ]
    }

    private static var listSummaryFields: [MaterializeFieldConfig] {
        [
            field("title", "Title", "text", "title"),
            field("description", "Description", "textarea", "description"),
            field("rowCount", "Rows", "number", "rowCount"),
            field("isPublic", "Public", "boolean", "isPublic"),
        ]
    }

    private static var documentFields: [MaterializeFieldConfig] {
        [
            field("section", "Section", "text", "section"),
            field("text", "Text", "textarea", "text"),
            field("type", "Type", "text", "type"),
        ]
    }

    /// Clone a source list's schema into editable column configs (identity mapping).
    ///
    /// A `select`/`multiselect` column is downgraded to `text` when the source
    /// carries no options: the server's DSL validator rejects an optionless
    /// select outright, and GitHub-backed lists hit exactly that — their
    /// synthetic `labels`/`assignees` columns are multiselect with no options.
    private static func fields(from props: [ListPropertyDef]) -> [MaterializeFieldConfig] {
        props
            .sorted { $0.displayOrder < $1.displayOrder }
            .map { prop in
                let options = prop.selectOptions.isEmpty ? nil : prop.selectOptions
                let needsOptions = prop.propertyType == "select" || prop.propertyType == "multiselect"
                return MaterializeFieldConfig(
                    propertyKey: prop.propertyKey,
                    propertyName: prop.propertyName,
                    propertyType: (needsOptions && options == nil) ? "text" : prop.propertyType,
                    isRequired: prop.isRequired ? true : nil,
                    options: options,
                    sourceKey: prop.propertyKey
                )
            }
    }

    static func inferSchema(for source: MaterializeLocalSource) -> [MaterializeFieldConfig] {
        switch source {
        case .messages:
            return messageFields
        case .rows(_, _, let fields, _):
            return self.fields(from: fields)
        case .lists(let lists):
            return lists.count == 1 ? fields(from: lists[0].fields) : listSummaryFields
        case .document:
            return documentFields
        }
    }

    // MARK: - Default titles

    static func defaultListTitle(for source: MaterializeLocalSource) -> String {
        switch source {
        case .messages(let messages):
            if messages.count == 1 {
                return "Message by @\(messages[0].user?.username ?? "unknown")"
            }
            return "\(messages.count) messages"
        case .rows(_, let listTitle, _, _):
            return listTitle
        case .lists(let lists):
            return lists.count == 1 ? lists[0].listTitle : "\(lists.count) lists"
        case .document(let doc):
            return doc.title
        }
    }

    /// The document title seeded into the sheet.
    ///
    /// The backend derives its own default when `docConfig.title` is omitted
    /// (`defaultDocPaths`), using helpers iOS does not mirror. Rather than guess
    /// at those, the sheet shows this simpler default and **sends it**, so what
    /// the user sees is what gets created. `relativePath` is still left to the
    /// server so the canonical path stays server-owned.
    static func defaultDocumentTitle(for source: MaterializeLocalSource) -> String {
        switch source {
        case .messages(let messages):
            if messages.count == 1, let first = messages.first {
                return firstLine(of: first.content, fallback: "Message by @\(first.user?.username ?? "unknown")")
            }
            return "\(messages.count) messages"
        case .rows(_, let listTitle, _, let rows):
            return rows.count == 1 ? "\(listTitle) (row)" : listTitle
        case .lists(let lists):
            return lists.count == 1 ? lists[0].listTitle : "\(lists.count) lists"
        case .document(let doc):
            return "Copy of \(doc.title)"
        }
    }

    private static func firstLine(of content: String, fallback: String) -> String {
        let line = content
            .components(separatedBy: .newlines)
            .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })?
            .trimmingCharacters(in: .whitespaces) ?? ""
        guard !line.isEmpty else { return fallback }
        return line.count > 120 ? String(line.prefix(117)) + "…" : line
    }

    // MARK: - Source reference (what actually goes over the wire)

    static func sourceRef(for source: MaterializeLocalSource) -> MaterializeSourceRef {
        switch source {
        case .messages(let messages):
            return .messages(messageIds: messages.map(\.id))
        case .lists(let lists):
            return .lists(listIds: lists.map(\.listId))
        case .rows(let listId, _, _, let rows):
            return .rows(listId: listId, rowIds: rows.map(\.id))
        case .document(let doc):
            return .document(documentId: doc.documentId)
        }
    }

    // MARK: - Preview projection

    /// Preview rows as display strings, keyed by `propertyKey`. Advisory only —
    /// the server re-derives the real values from authoritative data.
    static func previewRows(for source: MaterializeLocalSource,
                            fields: [MaterializeFieldConfig],
                            limit: Int = 25) -> [[String: String]] {
        let rows: [[String: String]]
        switch source {
        case .messages(let messages):
            rows = messages.map { message in
                project(fields) { messageValue(message, key: $0) }
            }
        case .rows(_, _, _, let items):
            rows = items.map { item in
                project(fields) { item.rowData[$0]?.displayString ?? "" }
            }
        case .lists(let lists):
            if lists.count == 1 {
                rows = lists[0].rows.map { item in
                    project(fields) { item.rowData[$0]?.displayString ?? "" }
                }
            } else {
                rows = lists.map { list in
                    project(fields) { listSummaryValue(list, key: $0) }
                }
            }
        case .document(let doc):
            rows = MarkdownBlocks.rowBlocks(doc.content).map { block in
                project(fields) { blockValue(block, key: $0) }
            }
        }
        return Array(rows.prefix(limit))
    }

    private static func project(_ fields: [MaterializeFieldConfig],
                                _ value: (String) -> String) -> [String: String] {
        var row: [String: String] = [:]
        for field in fields {
            row[field.propertyKey] = field.sourceKey.map(value) ?? ""
        }
        return row
    }

    private static func messageValue(_ message: Message, key: String) -> String {
        switch key {
        case "content":
            return message.content
        case "author":
            guard let user = message.user else { return "" }
            if let displayName = user.displayName, !displayName.isEmpty {
                return "\(displayName) (@\(user.username))"
            }
            return "@\(user.username)"
        case "posted":
            return postedFormatter.string(from: parseISO(message.createdAt) ?? Date())
        case "links":
            return (message.linkMetadata?.links ?? []).map(\.url).joined(separator: "\n")
        case "tags":
            return (message.tags ?? []).joined(separator: ", ")
        case "images":
            return (message.imageUrls ?? []).joined(separator: "\n")
        default:
            return ""
        }
    }

    private static func listSummaryValue(_ list: MaterializeListSummary, key: String) -> String {
        switch key {
        case "title": return list.listTitle
        case "description": return list.description ?? ""
        case "rowCount": return String(list.totalRows)
        case "isPublic": return list.isPublic ? "true" : "false"
        default: return ""
        }
    }

    private static func blockValue(_ block: MarkdownBlocks.Block, key: String) -> String {
        switch key {
        case "section": return block.section
        case "text": return block.text
        case "type": return block.type.rawValue
        case "level": return block.level == 0 ? "" : String(block.level)
        default: return ""
        }
    }

    private static let postedFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private static func parseISO(_ string: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: string) { return date }
        iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: string)
    }
}
