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

/// Persisted per-user offline document state (cached under `"<userId>_docsync"`):
/// the merged **non-deleted** folders/documents plus the sync cursor.
struct DocumentSyncState: Codable {
    var folders: [DocumentFolder]
    var documents: [Document]
    var lastSyncAt: String?

    init(folders: [DocumentFolder] = [], documents: [Document] = [], lastSyncAt: String? = nil) {
        self.folders = folders
        self.documents = documents
        self.lastSyncAt = lastSyncAt
    }
}
