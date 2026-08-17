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
    /// Merges a pull `delta` into `state`. Document rows whose id is in
    /// `protectingIds` (Slice-3 conflicting dirty docs whose local edit must stay
    /// live) are left untouched — neither upserted nor tombstoned — so the server
    /// version never clobbers the local one. Folders are never protected. The
    /// default empty set preserves the pre-Slice-3 last-writer-wins behavior.
    static func apply(delta: DocumentSyncResponse,
                      to state: DocumentSyncState,
                      protectingIds: Set<String> = []) -> DocumentSyncState {
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
            if protectingIds.contains(document.id) { continue }
            if document.deletedAt != nil {
                documents.removeAll { $0.id == document.id }
            } else {
                upsert(document, into: &documents)
            }
        }

        return DocumentSyncState(
            folders: folders,
            documents: documents,
            lastSyncAt: delta.lastSyncAt ?? state.lastSyncAt,
            outbox: state.outbox,
            localStates: state.localStates,
            baselines: state.baselines
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
