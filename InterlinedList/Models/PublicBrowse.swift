//
//  PublicBrowse.swift
//  InterlinedList
//

import Foundation

/// A lightweight reference to a public list (child or ancestor in breadcrumbs).
struct PublicListSummary: Identifiable, Decodable {
    let id: String
    let title: String?

    enum CodingKeys: String, CodingKey { case id, title, name }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = (try? c.decode(String.self, forKey: .title)) ?? (try? c.decode(String.self, forKey: .name))
    }
}

struct PublicListOwner: Decodable {
    let username: String?
    let displayName: String?
}

/// Public list metadata. Tolerates both the flat docs shape
/// (`{ id, title, schema, owner, ... }`) and the wrapped OpenAPI shape
/// (`{ list: { id, title, children }, ancestors: [...] }`).
struct PublicListDetail: Decodable {
    let id: String
    let title: String
    let description: String?
    let isPublic: Bool?
    /// Schema as a DSL string ("Title:text, Author:text"), when provided.
    let schema: String?
    let owner: PublicListOwner?
    let properties: [ListPropertyDef]?
    let children: [PublicListSummary]?
    let ancestors: [PublicListSummary]?

    private enum RootKeys: String, CodingKey { case list, ancestors }
    private enum FieldKeys: String, CodingKey {
        case id, title, name, description, isPublic, schema, owner, properties, children
    }

    init(from decoder: Decoder) throws {
        let root = try decoder.container(keyedBy: RootKeys.self)
        // Prefer the nested `list` object when present; otherwise read from the root.
        let source: KeyedDecodingContainer<FieldKeys>
        if root.contains(.list) {
            source = try root.nestedContainer(keyedBy: FieldKeys.self, forKey: .list)
            ancestors = try? root.decode([PublicListSummary].self, forKey: .ancestors)
        } else {
            source = try decoder.container(keyedBy: FieldKeys.self)
            ancestors = nil
        }
        id = try source.decode(String.self, forKey: .id)
        title = (try? source.decode(String.self, forKey: .title))
            ?? (try? source.decode(String.self, forKey: .name)) ?? "Untitled"
        description = try? source.decode(String.self, forKey: .description)
        isPublic = try? source.decode(Bool.self, forKey: .isPublic)
        schema = try? source.decode(String.self, forKey: .schema)
        owner = try? source.decode(PublicListOwner.self, forKey: .owner)
        properties = try? source.decode([ListPropertyDef].self, forKey: .properties)
        children = try? source.decode([PublicListSummary].self, forKey: .children)
    }
}

/// Public list data rows + optional schema, with pagination. Tolerates `rows`
/// or `items` for the row array and an optional top-level `properties` block.
struct PublicListData: Decodable {
    let rows: [ListItem]
    let properties: [ListPropertyDef]?
    let pagination: Pagination?

    enum CodingKeys: String, CodingKey { case rows, items, properties, pagination }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let rowsByKey = try? c.decode([ListItem].self, forKey: .rows)
        let itemsByKey = try? c.decode([ListItem].self, forKey: .items)
        rows = rowsByKey ?? itemsByKey ?? []
        properties = try? c.decode([ListPropertyDef].self, forKey: .properties)
        pagination = try? c.decode(Pagination.self, forKey: .pagination)
    }
}

// MARK: - Public documents

struct PublicDocumentSummary: Identifiable, Decodable {
    let id: String
    let title: String
    let folderId: String?
    let relativePath: String?
    let createdAt: String?
    let updatedAt: String?
}

struct PublicDocumentFolder: Identifiable, Decodable {
    let id: String
    let name: String
    let parentId: String?
}

struct PublicDocumentsResponse: Decodable {
    let documents: [PublicDocumentSummary]
    let folders: [PublicDocumentFolder]
}
