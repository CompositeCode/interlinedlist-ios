//
//  List.swift
//  InterlinedList
//

import Foundation

// MARK: - JSON value type for dynamic rowData fields

enum JSONValue: Codable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    var displayString: String {
        switch self {
        case .string(let s): return s
        case .number(let n): return n.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(n)) : String(n)
        case .bool(let b): return b ? "Yes" : "No"
        case .null: return ""
        }
    }

    var boolValue: Bool? {
        if case .bool(let b) = self { return b }
        return nil
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let b = try? c.decode(Bool.self) { self = .bool(b); return }
        if let n = try? c.decode(Double.self) { self = .number(n); return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        if c.decodeNil() { self = .null; return }
        throw DecodingError.typeMismatch(JSONValue.self, .init(codingPath: decoder.codingPath, debugDescription: "Unsupported JSON value type"))
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .number(let n): try c.encode(n)
        case .bool(let b): try c.encode(b)
        case .null: try c.encodeNil()
        }
    }
}

// MARK: - List property schema

struct ListPropertyDef: Codable, Identifiable {
    let id: String
    let propertyKey: String
    let propertyName: String
    let propertyType: String
    let displayOrder: Int
    let isVisible: Bool
    let isRequired: Bool
    let defaultValue: String?
    let helpText: String?
    let placeholder: String?
}

struct ListDetailData: Decodable {
    let id: String
    let title: String
    let properties: [ListPropertyDef]
}

struct ListDetailResponse: Decodable {
    let data: ListDetailData
}

/// One property in the structured PUT /api/lists/[id]/schema body.
/// `id` present → update in place (preserve row data); `id` nil → create new.
/// Properties omitted from the array are soft-deleted (use `?force=true` to drop
/// columns that still contain data). Array order is authoritative for displayOrder.
struct SchemaPropertyInput: Encodable {
    let id: String?
    let propertyKey: String
    let propertyName: String
    let propertyType: String
    let displayOrder: Int
    let isVisible: Bool
    let isRequired: Bool
    let defaultValue: String?
    let helpText: String?
    let placeholder: String?
}

struct StructuredSchemaBody: Encodable {
    let properties: [SchemaPropertyInput]
}

struct SchemaUpdateResponse: Decodable {
    let properties: [ListPropertyDef]?
}

/// The DSL object `POST /api/lists` expects under its `schema` key. The backend's
/// `validateDSLSchema` requires an object (`{ name, fields: [{ key, type, label }] }`)
/// and rejects anything else with "DSL must be an object". Note: the published API
/// docs at /help/api still show the legacy `"Name:type"` DSL *string* — that form no
/// longer works; the backend source is authoritative.
struct ListSchemaDSL: Encodable {
    let name: String
    let description: String?
    let fields: [Field]

    struct Field: Encodable {
        let key: String
        let label: String
        let type: String
        let displayOrder: Int
        let required: Bool
        let visible: Bool
    }
}

// MARK: - Core list models

struct UserList: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let description: String?
    /// Parent list id for list-in-list nesting (backend `parentId` column).
    let parentId: String?
    let isPublic: Bool?
    let createdAt: String
    let updatedAt: String?
    let itemCount: Int?
    /// "github" for GitHub-backed lists, "local" (or nil on older data) otherwise.
    let source: String?
    /// "owner/repo" for a GitHub-backed list; nil for local lists.
    let githubRepo: String?
    /// Refresh metadata for GitHub-backed lists (only present on `GET /api/lists`).
    let githubMeta: GitHubListMeta?
    /// The id of the list's owner (backend `userId`). `GET /api/lists` is
    /// owner-scoped so today this always equals the current user, but decoding it
    /// lets owner-only UI gate correctly if the payload ever includes shared-in
    /// lists. Optional because older data / other endpoints may omit it.
    let ownerId: String?

    /// True when this list mirrors a GitHub repository's issues.
    var isGitHubBacked: Bool { source == "github" }

    /// Whether `userId` identifies `user` as the owner. When `ownerId` is absent
    /// (endpoint didn't send it) we optimistically treat the list as owned so
    /// existing owner-scoped screens keep working.
    func isOwned(by userId: String?) -> Bool {
        guard let ownerId, !ownerId.isEmpty else { return true }
        return ownerId == userId
    }

    // Server sends "title" for name and "parentId" for list-in-list nesting.
    // convertFromSnakeCase is bypassed when CodingKeys are present, so spell the
    // exact JSON keys (the bare cases resolve to their own names, i.e. "parentId").
    // source/githubRepo/githubMeta arrive camelCase (backend `serialize` preserves keys).
    enum CodingKeys: String, CodingKey {
        case id, description, createdAt, updatedAt, itemCount, isPublic
        case name = "title"
        case parentId
        case source, githubRepo, githubMeta
        case ownerId = "userId"
    }

    // Explicit memberwise init keeps the GitHub fields optional at call sites
    // (previews, tests) without forcing every constructor to pass them.
    init(id: String, name: String, description: String?, parentId: String? = nil,
         isPublic: Bool?, createdAt: String, updatedAt: String?,
         itemCount: Int?, source: String? = nil, githubRepo: String? = nil,
         githubMeta: GitHubListMeta? = nil, ownerId: String? = nil) {
        self.id = id
        self.name = name
        self.description = description
        self.parentId = parentId
        self.isPublic = isPublic
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.itemCount = itemCount
        self.source = source
        self.githubRepo = githubRepo
        self.githubMeta = githubMeta
        self.ownerId = ownerId
    }
}

struct ListItem: Identifiable, Codable {
    let id: String
    let rowData: [String: JSONValue]
    let rowNumber: Int?
    let createdAt: String?
}

// MARK: - Tree node

struct ListTreeNode: Identifiable {
    let id: String
    let name: String
    var children: [ListTreeNode]?  // nil = leaf list, non-nil = parent with child lists
    let list: UserList?

    static func buildTree(lists: [UserList]) -> [ListTreeNode] {
        let knownListIds = Set(lists.map { $0.id })

        // Builds a node for a list, recursing into child lists (parentId → this list's id).
        // API data is assumed acyclic; guard against any circular edge by ignoring a child
        // whose id equals the ancestor's.
        func listNode(_ list: UserList) -> ListTreeNode {
            let children = lists.filter { child in
                guard let pid = child.parentId, !pid.isEmpty else { return false }
                return pid == list.id && child.id != list.id
            }.map { listNode($0) }
            return ListTreeNode(id: list.id, name: list.name,
                                children: children.isEmpty ? nil : children,
                                list: list)
        }

        // A list shows at root unless it nests under a known parent list; an empty or
        // orphaned parentId falls through to root (CLAUDE.md: parentId may arrive "").
        let rootLists = lists.filter { list in
            if let pid = list.parentId, !pid.isEmpty, knownListIds.contains(pid) { return false }
            return true
        }.map { listNode($0) }
        return rootLists
    }
}

// MARK: - API response wrappers

struct ListsResponse: Decodable {
    let lists: [UserList]
}

// MARK: - List connections

/// A list's relationship to another list, from the perspective of one side of a
/// connection. The backend stores a directed edge `fromList → toList`; by
/// convention (matching the web ERD) the `fromList` is the parent of the `toList`.
enum ListRelationship: Equatable {
    case parent
    case child
}

struct ListConnection: Identifiable, Codable {
    let id: String
    let fromListId: String
    let toListId: String
    let label: String?
    let createdAt: String?

    /// The id of the list on the other end of this connection, relative to `listId`.
    func otherListId(relativeTo listId: String) -> String {
        fromListId == listId ? toListId : fromListId
    }

    /// From `listId`'s perspective, is the other list its parent or its child?
    /// `fromList` is the parent, so if `listId` is the `fromList` the other side
    /// is its child; otherwise the other side is its parent.
    func relationship(relativeTo listId: String) -> ListRelationship {
        fromListId == listId ? .child : .parent
    }
}

struct ConnectionsResponse: Decodable {
    let connections: [ListConnection]
}
