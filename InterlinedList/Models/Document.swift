//
//  Document.swift
//  InterlinedList
//

import Foundation

struct Document: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let content: String?
    let folderId: String?
    let isPublic: Bool?
    let createdAt: String?
    let updatedAt: String?
    /// Soft-delete tombstone from `GET /api/documents/sync`. `nil` on every other
    /// endpoint. A non-nil value means the row was deleted server-side.
    let deletedAt: String?

    init(id: String, title: String, content: String? = nil, folderId: String? = nil,
         isPublic: Bool? = nil, createdAt: String? = nil, updatedAt: String? = nil,
         deletedAt: String? = nil) {
        self.id = id
        self.title = title
        self.content = content
        self.folderId = folderId
        self.isPublic = isPublic
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}

struct DocumentFolder: Codable, Identifiable {
    let id: String
    let name: String
    let parentId: String?
    let updatedAt: String?
    /// Soft-delete tombstone from `GET /api/documents/sync`. See `Document.deletedAt`.
    let deletedAt: String?

    init(id: String, name: String, parentId: String? = nil,
         updatedAt: String? = nil, deletedAt: String? = nil) {
        self.id = id
        self.name = name
        self.parentId = parentId
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}

/// A starter document a subscriber can copy into a new document. `id` is the
/// source document's id (`templateDocumentId` for `POST /api/documents/from-template`).
struct DocumentTemplate: Codable, Identifiable {
    let id: String
    let title: String
    let relativePath: String?
}

struct DocumentTemplatesResponse: Codable {
    let templates: [DocumentTemplate]
}

struct DocumentsResponse: Codable {
    let documents: [Document]
}

struct DocumentFoldersResponse: Codable {
    let folders: [DocumentFolder]
}
