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
    /// True for server-managed columns the client must not edit (e.g. a GitHub
    /// issue's number/url/timestamps). Absent for local lists → defaults false.
    let isReadOnly: Bool
    /// Allowed values for `select`/`multiselect` fields, from the backend's
    /// `validationRules.options`. Empty when the field isn't an enumerated type
    /// or the options are loaded elsewhere (GitHub labels/assignees send `[]`).
    let selectOptions: [String]

    enum CodingKeys: String, CodingKey {
        case id, propertyKey, propertyName, propertyType, displayOrder
        case isVisible, isRequired, defaultValue, helpText, placeholder
        case isReadOnly, validationRules
    }

    private enum ValidationRulesKeys: String, CodingKey {
        case options
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        propertyKey = try c.decode(String.self, forKey: .propertyKey)
        propertyName = try c.decode(String.self, forKey: .propertyName)
        propertyType = try c.decode(String.self, forKey: .propertyType)
        displayOrder = try c.decode(Int.self, forKey: .displayOrder)
        isVisible = try c.decode(Bool.self, forKey: .isVisible)
        isRequired = try c.decode(Bool.self, forKey: .isRequired)
        defaultValue = try c.decodeIfPresent(String.self, forKey: .defaultValue)
        helpText = try c.decodeIfPresent(String.self, forKey: .helpText)
        placeholder = try c.decodeIfPresent(String.self, forKey: .placeholder)
        isReadOnly = try c.decodeIfPresent(Bool.self, forKey: .isReadOnly) ?? false
        if let rules = try? c.nestedContainer(keyedBy: ValidationRulesKeys.self, forKey: .validationRules) {
            selectOptions = (try? rules.decodeIfPresent([String].self, forKey: .options)) ?? []
        } else {
            selectOptions = []
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(propertyKey, forKey: .propertyKey)
        try c.encode(propertyName, forKey: .propertyName)
        try c.encode(propertyType, forKey: .propertyType)
        try c.encode(displayOrder, forKey: .displayOrder)
        try c.encode(isVisible, forKey: .isVisible)
        try c.encode(isRequired, forKey: .isRequired)
        try c.encodeIfPresent(defaultValue, forKey: .defaultValue)
        try c.encodeIfPresent(helpText, forKey: .helpText)
        try c.encodeIfPresent(placeholder, forKey: .placeholder)
        try c.encode(isReadOnly, forKey: .isReadOnly)
        if !selectOptions.isEmpty {
            var rules = c.nestedContainer(keyedBy: ValidationRulesKeys.self, forKey: .validationRules)
            try rules.encode(selectOptions, forKey: .options)
        }
    }

    // Explicit memberwise init keeps the GitHub-schema fields optional at call
    // sites (previews, tests) without threading them through every constructor.
    init(id: String, propertyKey: String, propertyName: String, propertyType: String,
         displayOrder: Int, isVisible: Bool, isRequired: Bool, defaultValue: String?,
         helpText: String?, placeholder: String?, isReadOnly: Bool = false,
         selectOptions: [String] = []) {
        self.id = id
        self.propertyKey = propertyKey
        self.propertyName = propertyName
        self.propertyType = propertyType
        self.displayOrder = displayOrder
        self.isVisible = isVisible
        self.isRequired = isRequired
        self.defaultValue = defaultValue
        self.helpText = helpText
        self.placeholder = placeholder
        self.isReadOnly = isReadOnly
        self.selectOptions = selectOptions
    }
}

extension ListPropertyDef {
    /// The fixed schema for GitHub-backed lists, mirroring the backend's
    /// `getGitHubListSchema()`. The server now returns this schema in
    /// `GET /api/lists/:id` `properties` (their columns are synthetic issue
    /// fields, not stored `listProperty` rows). This client copy is a **fallback**
    /// used only when the fetched schema is empty (older/undeployed backend or a
    /// transient response), so the add/edit form and row display still work. Keep
    /// in sync with the backend if the issue schema ever changes.
    static func gitHubIssueSchema() -> [ListPropertyDef] {
        [
            ListPropertyDef(id: "gh_number", propertyKey: "number", propertyName: "Issue #", propertyType: "number", displayOrder: 0, isVisible: true, isRequired: false, defaultValue: nil, helpText: "Auto-assigned by GitHub when the issue is created", placeholder: nil, isReadOnly: true),
            ListPropertyDef(id: "gh_title", propertyKey: "title", propertyName: "Title", propertyType: "text", displayOrder: 1, isVisible: true, isRequired: true, defaultValue: nil, helpText: nil, placeholder: nil),
            ListPropertyDef(id: "gh_body", propertyKey: "body", propertyName: "Body", propertyType: "textarea", displayOrder: 2, isVisible: true, isRequired: false, defaultValue: nil, helpText: nil, placeholder: nil),
            ListPropertyDef(id: "gh_state", propertyKey: "state", propertyName: "State", propertyType: "select", displayOrder: 3, isVisible: true, isRequired: false, defaultValue: "open", helpText: nil, placeholder: nil, selectOptions: ["open", "closed"]),
            ListPropertyDef(id: "gh_labels", propertyKey: "labels", propertyName: "Labels", propertyType: "multiselect", displayOrder: 4, isVisible: true, isRequired: false, defaultValue: nil, helpText: "Comma-separated", placeholder: nil),
            ListPropertyDef(id: "gh_assignees", propertyKey: "assignees", propertyName: "Assignees", propertyType: "multiselect", displayOrder: 5, isVisible: true, isRequired: false, defaultValue: nil, helpText: "Comma-separated", placeholder: nil),
            ListPropertyDef(id: "gh_url", propertyKey: "url", propertyName: "Link", propertyType: "url", displayOrder: 6, isVisible: true, isRequired: false, defaultValue: nil, helpText: nil, placeholder: nil, isReadOnly: true),
            ListPropertyDef(id: "gh_created_at", propertyKey: "created_at", propertyName: "Created", propertyType: "datetime", displayOrder: 7, isVisible: true, isRequired: false, defaultValue: nil, helpText: nil, placeholder: nil, isReadOnly: true),
            ListPropertyDef(id: "gh_updated_at", propertyKey: "updated_at", propertyName: "Updated", propertyType: "datetime", displayOrder: 8, isVisible: true, isRequired: false, defaultValue: nil, helpText: nil, placeholder: nil, isReadOnly: true),
        ]
    }

    /// Picks the most meaningful column to headline a row, rather than blindly
    /// taking the first field (which is often an id/number/timestamp). Prefers a
    /// human-readable "name"-like field, then the first editable text field, then
    /// any editable field, then whatever is visible.
    static func primaryDisplayField(from props: [ListPropertyDef]) -> ListPropertyDef? {
        let visible = props.filter { $0.isVisible }.sorted { $0.displayOrder < $1.displayOrder }
        guard !visible.isEmpty else { return nil }

        let preferredKeys = ["title", "name", "subject", "summary", "heading", "headline", "task", "question", "label"]
        for key in preferredKeys {
            if let match = visible.first(where: { $0.propertyKey.lowercased() == key || $0.propertyName.lowercased() == key }) {
                return match
            }
        }
        if let text = visible.first(where: { ($0.propertyType == "text" || $0.propertyType == "textarea") && !$0.isReadOnly }) {
            return text
        }
        if let editable = visible.first(where: { !$0.isReadOnly }) {
            return editable
        }
        return visible.first
    }
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
