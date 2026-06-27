//
//  Document.swift
//  InterlinedList
//

import Foundation

struct Document: Codable, Identifiable {
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

struct DocumentsResponse: Codable {
    let documents: [Document]
}

struct DocumentFoldersResponse: Codable {
    let folders: [DocumentFolder]
}
