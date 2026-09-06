//
//  Materialize.swift
//  InterlinedList
//

import Foundation

/// Wire types for "Create from…" (`POST /api/materialize`), which turns an
/// existing object — message(s), list(s), list rows, or a document — into a new
/// List, a new Document, or both.
///
/// The request carries **id-only references**. The server re-fetches and
/// authorizes every referenced id under the calling user and re-derives each
/// column's values from that authoritative data via `sourceKey`; client-supplied
/// cell values are never trusted. So the preview this app renders is advisory —
/// the server's output is the real thing.
///
/// The body is camelCase, so it must go out through `postCamel`, not `post`.

enum MaterializeTarget: String, Codable, CaseIterable, Identifiable {
    case list
    case doc
    case both

    var id: String { rawValue }

    var label: String {
        switch self {
        case .list: return "To List"
        case .doc: return "To Doc"
        case .both: return "To List & Doc"
        }
    }

    var createsList: Bool { self == .list || self == .both }
    var createsDocument: Bool { self == .doc || self == .both }
}

/// The id-only source reference sent over the wire.
///
/// The server also accepts a `docElements` kind (a document id plus selected
/// markdown), used by the web editor's text-selection menu. iOS has no
/// equivalent selection affordance yet, so it is deliberately not modeled here.
enum MaterializeSourceRef: Equatable {
    case messages(messageIds: [String])
    case lists(listIds: [String])
    case rows(listId: String, rowIds: [String])
    case document(documentId: String)
}

extension MaterializeSourceRef: Encodable {
    private enum CodingKeys: String, CodingKey {
        case kind, messageIds, listIds, listId, rowIds, documentId
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .messages(let ids):
            try c.encode("messages", forKey: .kind)
            try c.encode(ids, forKey: .messageIds)
        case .lists(let ids):
            try c.encode("lists", forKey: .kind)
            try c.encode(ids, forKey: .listIds)
        case .rows(let listId, let rowIds):
            try c.encode("rows", forKey: .kind)
            try c.encode(listId, forKey: .listId)
            try c.encode(rowIds, forKey: .rowIds)
        case .document(let documentId):
            try c.encode("document", forKey: .kind)
            try c.encode(documentId, forKey: .documentId)
        }
    }
}

/// One column in the finalize sheet's schema editor.
///
/// `sourceKey` maps the column back to a source attribute so the **server** can
/// re-derive its values. `nil` means a user-added empty column and is encoded as
/// an explicit `null` (not omitted) to match the documented contract.
struct MaterializeFieldConfig: Identifiable, Equatable {
    var propertyKey: String
    var propertyName: String
    var propertyType: String
    var isRequired: Bool?
    var options: [String]?
    var sourceKey: String?

    var id: String { propertyKey }

    /// Column types offered by the editor. `textarea` is included because the
    /// server's inferred schemas use it for long-form columns (message content,
    /// document text).
    static let supportedTypes: [String] = [
        "text", "textarea", "number", "boolean", "date", "url", "email",
    ]

    init(propertyKey: String,
         propertyName: String,
         propertyType: String,
         isRequired: Bool? = nil,
         options: [String]? = nil,
         sourceKey: String?) {
        self.propertyKey = propertyKey
        self.propertyName = propertyName
        self.propertyType = propertyType
        self.isRequired = isRequired
        self.options = options
        self.sourceKey = sourceKey
    }
}

extension MaterializeFieldConfig: Encodable {
    private enum CodingKeys: String, CodingKey {
        case propertyKey, propertyName, propertyType, isRequired, options, sourceKey
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(propertyKey, forKey: .propertyKey)
        try c.encode(propertyName, forKey: .propertyName)
        try c.encode(propertyType, forKey: .propertyType)
        try c.encodeIfPresent(isRequired, forKey: .isRequired)
        try c.encodeIfPresent(options, forKey: .options)
        if let sourceKey {
            try c.encode(sourceKey, forKey: .sourceKey)
        } else {
            try c.encodeNil(forKey: .sourceKey)
        }
    }
}

struct MaterializeListConfig: Encodable, Equatable {
    var title: String
    var description: String?
    var isPublic: Bool?
    var fields: [MaterializeFieldConfig]
    /// Defaults to `true` server-side; only an explicit `false` creates an
    /// empty, columns-only list.
    var includeData: Bool?
}

enum MaterializeDocListStyle: String, Codable, CaseIterable, Identifiable {
    case numbered
    case bulleted

    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

enum MaterializeDocRowDataStyle: String, Codable, CaseIterable, Identifiable {
    case inline
    case subItems = "sub-items"

    var id: String { rawValue }
    var label: String { self == .inline ? "Inline" : "Sub-items" }
}

struct MaterializeDocConfig: Encodable, Equatable {
    var title: String
    /// Omitted so the server derives its canonical path (it appends `.md` and
    /// slugs from the source). Set only when the user supplies one.
    var relativePath: String?
    var isPublic: Bool?
    /// Only meaningful for list / row sources.
    var listStyle: MaterializeDocListStyle?
    var rowDataStyle: MaterializeDocRowDataStyle?
}

struct MaterializeRequest: Encodable {
    let target: MaterializeTarget
    let source: MaterializeSourceRef
    let listConfig: MaterializeListConfig?
    let docConfig: MaterializeDocConfig?
}

struct MaterializeCreatedRef: Decodable, Equatable {
    let id: String
    let title: String
}

struct MaterializeResult: Decodable, Equatable {
    let list: MaterializeCreatedRef?
    let document: MaterializeCreatedRef?
}
