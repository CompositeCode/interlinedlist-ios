//
//  DocumentSyncMerge.swift
//  InterlinedList
//

import Foundation

/// Pure, deterministic merge of a `GET /api/documents/sync` delta into a cached
/// `DocumentSyncState`. No I/O. For each delta row: a non-nil `deletedAt`
/// removes the row by `id` (tombstone); otherwise the row is upserted by `id`.
/// The delta's `lastSyncAt` becomes the new cursor. An empty delta is a no-op
/// except that a non-nil cursor still advances.
enum DocumentSyncMerge {
    static func apply(delta: DocumentSyncResponse, to state: DocumentSyncState) -> DocumentSyncState {
        var folders = state.folders
        var documents = state.documents

        for folder in delta.folders {
            if folder.deletedAt != nil {
                folders.removeAll { $0.id == folder.id }
            } else {
                upsert(folder, into: &folders)
            }
        }

        for document in delta.documents {
            if document.deletedAt != nil {
                documents.removeAll { $0.id == document.id }
            } else {
                upsert(document, into: &documents)
            }
        }

        return DocumentSyncState(
            folders: folders,
            documents: documents,
            lastSyncAt: delta.lastSyncAt ?? state.lastSyncAt
        )
    }

    private static func upsert(_ folder: DocumentFolder, into folders: inout [DocumentFolder]) {
        if let idx = folders.firstIndex(where: { $0.id == folder.id }) {
            folders[idx] = folder
        } else {
            folders.append(folder)
        }
    }

    private static func upsert(_ document: Document, into documents: inout [Document]) {
        if let idx = documents.firstIndex(where: { $0.id == document.id }) {
            documents[idx] = document
        } else {
            documents.append(document)
        }
    }
}
