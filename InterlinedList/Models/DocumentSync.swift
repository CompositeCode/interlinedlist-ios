//
//  DocumentSync.swift
//  InterlinedList
//

import Foundation

/// Response of `GET /api/documents/sync`. A **delta** since the supplied
/// `lastSyncAt` cursor, or **full state** when no cursor is sent. Rows with a
/// non-nil `deletedAt` are tombstones (deleted server-side). The response
/// `lastSyncAt` is the new cursor to persist for the next pull.
struct DocumentSyncResponse: Codable {
    let folders: [DocumentFolder]
    let documents: [Document]
    let lastSyncAt: String?

    init(folders: [DocumentFolder] = [], documents: [Document] = [], lastSyncAt: String? = nil) {
        self.folders = folders
        self.documents = documents
        self.lastSyncAt = lastSyncAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        folders = try container.decodeIfPresent([DocumentFolder].self, forKey: .folders) ?? []
        documents = try container.decodeIfPresent([Document].self, forKey: .documents) ?? []
        lastSyncAt = try container.decodeIfPresent(String.self, forKey: .lastSyncAt)
    }
}

/// One queued mutation for `POST /api/documents/sync`. The body is **camelCase**
/// (`op`/`type`/`path`/`data`) and only non-nil `data` keys are encoded, so a
/// delete carries just `{ "id": … }`. Ops accumulate in `DocumentSyncState.outbox`
/// and are drained on the next push cycle.
struct SyncOperation: Codable, Equatable {
    enum SyncOp: String, Codable {
        case create, update, delete
    }

    enum SyncEntityType: String, Codable {
        case document, folder
    }

    let op: SyncOp
    let type: SyncEntityType
    let path: String?
    let data: SyncOpData

    init(op: SyncOp, type: SyncEntityType, path: String? = nil, data: SyncOpData) {
        self.op = op
        self.type = type
        self.path = path
        self.data = data
    }
}

/// The `data` payload of a `SyncOperation`. Carries the document/folder fields the
/// server upserts by client-supplied `id`. Only non-nil keys are encoded so a
/// delete op (or a partial update) doesn't clobber unrelated fields server-side.
struct SyncOpData: Codable, Equatable {
    let id: String
    var folderId: String?
    var parentId: String?
    var name: String?
    var title: String?
    var content: String?
    var relativePath: String?
    var isPublic: Bool?

    init(id: String, folderId: String? = nil, parentId: String? = nil, name: String? = nil,
         title: String? = nil, content: String? = nil, relativePath: String? = nil,
         isPublic: Bool? = nil) {
        self.id = id
        self.folderId = folderId
        self.parentId = parentId
        self.name = name
        self.title = title
        self.content = content
        self.relativePath = relativePath
        self.isPublic = isPublic
    }

    private enum CodingKeys: String, CodingKey {
        case id, folderId, parentId, name, title, content, relativePath, isPublic
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(folderId, forKey: .folderId)
        try container.encodeIfPresent(parentId, forKey: .parentId)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(content, forKey: .content)
        try container.encodeIfPresent(relativePath, forKey: .relativePath)
        try container.encodeIfPresent(isPublic, forKey: .isPublic)
    }
}

/// Local sync state of a single document/folder relative to the server.
enum LocalSyncState: String, Codable {
    /// In sync with the server; no un-pushed edits.
    case synced
    /// Has un-pushed create/update edits queued in the outbox.
    case dirty
    /// Locally deleted; a delete op is queued (kept until the push confirms).
    case deleted
}

/// Persisted per-user offline document state (cached under `"<userId>_docsync"`):
/// the merged **non-deleted** folders/documents, the sync cursor, the pending
/// write `outbox`, and the per-id `localStates` map (which rows have un-pushed
/// edits). Persisted via the shared `DataCache`.
struct DocumentSyncState: Codable {
    var folders: [DocumentFolder]
    var documents: [Document]
    var lastSyncAt: String?
    var outbox: [SyncOperation]
    var localStates: [String: LocalSyncState]

    init(folders: [DocumentFolder] = [], documents: [Document] = [], lastSyncAt: String? = nil,
         outbox: [SyncOperation] = [], localStates: [String: LocalSyncState] = [:]) {
        self.folders = folders
        self.documents = documents
        self.lastSyncAt = lastSyncAt
        self.outbox = outbox
        self.localStates = localStates
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        folders = try container.decodeIfPresent([DocumentFolder].self, forKey: .folders) ?? []
        documents = try container.decodeIfPresent([Document].self, forKey: .documents) ?? []
        lastSyncAt = try container.decodeIfPresent(String.self, forKey: .lastSyncAt)
        // Tolerate a Slice-1 cache written before these fields existed.
        outbox = try container.decodeIfPresent([SyncOperation].self, forKey: .outbox) ?? []
        localStates = try container.decodeIfPresent([String: LocalSyncState].self, forKey: .localStates) ?? [:]
    }

    /// Ids that have un-pushed create/update edits (helper for the UI's
    /// "pending sync" affordance).
    var dirtyIds: Set<String> {
        Set(localStates.filter { $0.value == .dirty }.keys)
    }
}
