//
//  AIArtifact.swift
//  InterlinedList
//

import Foundation

/// The AI features exposed by `/api/ai/{suggest,generate}`. Raw values are the
/// wire `feature` strings.
enum AIFeature: String, Codable, Equatable {
    case writingAssist = "writing_assist"
    case poweredTemplate = "powered_template"
    case poweredDocument = "powered_document"
    case messageSeries = "message_series"
    case articleSeries = "article_series"
}

/// Presenting a feature-driven sheet needs identity.
extension AIFeature: Identifiable {
    var id: String { rawValue }
}

/// Writing Assistant actions (`context.action`).
enum AIWritingAction: String, CaseIterable, Identifiable, Equatable {
    case rewrite, tighten, expand, grammar, thread, tags

    var id: String { rawValue }

    var label: String {
        switch self {
        case .rewrite: return "Rewrite"
        case .tighten: return "Tighten to fit"
        case .expand: return "Expand"
        case .grammar: return "Fix grammar"
        case .thread: return "Split into thread"
        case .tags: return "Suggest tags"
        }
    }

    var systemImage: String {
        switch self {
        case .rewrite: return "wand.and.stars"
        case .tighten: return "arrow.down.right.and.arrow.up.left"
        case .expand: return "arrow.up.left.and.arrow.down.right"
        case .grammar: return "text.badge.checkmark"
        case .thread: return "list.number"
        case .tags: return "number"
        }
    }
}

/// Powered Document modes (`context.mode`).
enum AIDocumentMode: String, CaseIterable, Identifiable, Equatable {
    case article
    case fromList = "from_list"
    case fromArticle = "from_article"
    case researchUrl = "research_url"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .article: return "Article"
        case .fromList: return "Derived From List"
        case .fromArticle: return "Derived From Article"
        case .researchUrl: return "Research URL"
        }
    }

    var systemImage: String {
        switch self {
        case .article: return "doc.text"
        case .fromList: return "list.bullet.rectangle"
        case .fromArticle: return "doc.on.doc"
        case .researchUrl: return "link"
        }
    }
}

// MARK: - Artifact payloads

struct AIDocumentArtifact: Codable, Equatable {
    var title: String
    var markdown: String
    var outline: [String]?
    var isPublic: Bool?
}

struct AIMessageSeriesItem: Codable, Equatable, Identifiable {
    var order: Int
    var content: String
    var scheduledAt: String?
    var crossPostTargets: [String]?

    var id: Int { order }
}

struct AIMessageSeriesArtifact: Codable, Equatable {
    var listTitle: String
    var items: [AIMessageSeriesItem]
}

struct AIDocSeriesDocument: Codable, Equatable, Identifiable {
    var order: Int
    var title: String
    var outline: [String]?
    var markdown: String?

    var id: Int { order }
}

struct AIDocSeriesArtifact: Codable, Equatable {
    var folderTitle: String
    var documents: [AIDocSeriesDocument]
}

/// One column of a generated list schema, read out of the DSL for the preview.
/// The DSL itself is never rebuilt from these — it round-trips verbatim.
struct AIListField: Identifiable, Equatable {
    let id: String
    let label: String
    let type: String
    let isRequired: Bool
    let options: [String]
}

struct AIListArtifact: Codable, Equatable {
    var title: String
    var description: String?
    /// The model-authored DSL schema, kept verbatim — the server re-validates it
    /// at generate time and rejects a schema whose field keys were rewritten.
    var dsl: AIJSON
    var rows: [AIJSON]?

    /// Columns in `dsl.fields` order, for the preview.
    var fields: [AIListField] {
        guard let entries = dsl.objectValue?["fields"]?.arrayValue else { return [] }
        return entries.enumerated().compactMap { index, entry in
            guard let object = entry.objectValue else { return nil }
            let key = object["key"]?.stringValue
            guard let label = object["label"]?.stringValue ?? key else { return nil }
            return AIListField(
                id: key ?? "field-\(index)",
                label: label,
                type: object["type"]?.stringValue ?? "text",
                isRequired: object["required"] == .bool(true),
                options: object["options"]?.arrayValue?.compactMap { $0.stringValue } ?? []
            )
        }
    }

    /// Field labels in `dsl.fields` order.
    var fieldLabels: [String] { fields.map { $0.label } }

    /// A starter row rendered as `label: value` pairs in schema order.
    func rowSummary(_ row: AIJSON) -> [(label: String, value: String)] {
        guard let object = row.objectValue else { return [] }
        return fields.compactMap { field in
            guard let value = object[field.id], value != .null else { return nil }
            let rendered = value.displayString
            return rendered.isEmpty ? nil : (field.label, rendered)
        }
    }
}

/// The typed envelope `/suggest` returns and `/generate` accepts back. The wire
/// form is the payload's fields plus a `kind` discriminator.
enum AIArtifact: Codable, Equatable {
    case message(String)
    case tags([String])
    case thread([String])
    case document(AIDocumentArtifact)
    case messageSeries(AIMessageSeriesArtifact)
    case docSeries(AIDocSeriesArtifact)
    case list(AIListArtifact)

    var kind: String {
        switch self {
        case .message: return "message"
        case .tags: return "tags"
        case .thread: return "thread"
        case .document: return "document"
        case .messageSeries: return "message_series"
        case .docSeries: return "doc_series"
        case .list: return "list"
        }
    }

    private enum CodingKeys: String, CodingKey {
        case kind, content, tags, parts
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)
        switch kind {
        case "message":
            self = .message(try container.decode(String.self, forKey: .content))
        case "tags":
            self = .tags(try container.decode([String].self, forKey: .tags))
        case "thread":
            self = .thread(try container.decode([String].self, forKey: .parts))
        case "document":
            self = .document(try AIDocumentArtifact(from: decoder))
        case "message_series":
            self = .messageSeries(try AIMessageSeriesArtifact(from: decoder))
        case "doc_series":
            self = .docSeries(try AIDocSeriesArtifact(from: decoder))
        case "list":
            self = .list(try AIListArtifact(from: decoder))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .kind,
                in: container,
                debugDescription: "Unknown artifact kind \(kind)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        switch self {
        case .message(let content):
            try container.encode(content, forKey: .content)
        case .tags(let tags):
            try container.encode(tags, forKey: .tags)
        case .thread(let parts):
            try container.encode(parts, forKey: .parts)
        case .document(let payload):
            try payload.encode(to: encoder)
        case .messageSeries(let payload):
            try payload.encode(to: encoder)
        case .docSeries(let payload):
            try payload.encode(to: encoder)
        case .list(let payload):
            try payload.encode(to: encoder)
        }
    }
}

// MARK: - Generate result

/// What `/api/ai/generate` created. Exactly one shape arrives per feature: a
/// list, a document, an article-series folder, or a batch of scheduled messages.
struct AICreated: Codable, Equatable {
    var listId: String?
    var documentId: String?
    var folderId: String?
    var documentIds: [String]?
    var scheduledMessageIds: [String]?
    var firstScheduledAt: String?
    var lastScheduledAt: String?
}
