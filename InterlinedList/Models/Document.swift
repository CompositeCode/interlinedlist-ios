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
}

struct DocumentFolder: Codable, Identifiable {
    let id: String
    let name: String
    let parentId: String?
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
