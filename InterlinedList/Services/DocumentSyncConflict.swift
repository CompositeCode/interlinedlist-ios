//
//  DocumentSyncConflict.swift
//  InterlinedList
//

import Foundation

/// One detected conflict: a locally `.dirty` document whose server `updatedAt`
/// (carried in a fresh pull delta) is newer than the baseline we last synced it
/// at — i.e. someone edited it while we held un-pushed local changes. The
/// `serverDocument` is the still-intact server version we preserve as a copy.
struct ConflictInfo: Equatable {
    let id: String
    let serverDocument: Document
}

/// The conflict copy plus the `create` op that enqueues it, produced together so
/// the caller inserts and enqueues one consistent unit.
struct ConflictCopy: Equatable {
    let document: Document
    let operation: SyncOperation
}

/// Pure, deterministic conflict logic for the offline document sync cycle. No
/// I/O and no ambient `Date.now()`/`UUID()` — the caller injects the copy's date
/// and id so this is fully testable. Policy: **conflict-copy** — keep the local
/// edit live, and preserve the server version as a new document so nothing is lost.
enum DocumentSyncConflict {

    /// Detects conflicts in a pull `delta`: each delta document that is currently
    /// `dirty` locally AND whose server `updatedAt` is strictly newer than the
    /// baseline recorded for that id. Tombstoned rows (`deletedAt != nil`) and
    /// rows missing `updatedAt` are not conflicts. A dirty id with no recorded
    /// baseline (e.g. a purely local create the server hasn't acknowledged) is
    /// not a conflict — there is no shared history to diverge from.
    static func detectConflicts(delta: DocumentSyncResponse,
                                dirtyIds: Set<String>,
                                baselines: [String: String]) -> [ConflictInfo] {
        var conflicts: [ConflictInfo] = []
        for document in delta.documents {
            guard document.deletedAt == nil else { continue }
            guard dirtyIds.contains(document.id) else { continue }
            guard let baseline = baselines[document.id] else { continue }
            guard let serverUpdatedAt = document.updatedAt else { continue }
            if serverUpdatedAt > baseline {
                conflicts.append(ConflictInfo(id: document.id, serverDocument: document))
            }
        }
        return conflicts
    }

    /// Builds a conflict copy of a **server** document: a NEW document carrying a
    /// caller-supplied `newId`, a suffixed title, and the server's
    /// `content`/`folderId`/`isPublic`. Emits the paired `create` `SyncOperation`
    /// so the copy pushes to the server on the next drain.
    static func makeConflictCopy(server: Document, date: Date, newId: String) -> ConflictCopy {
        let title = conflictCopyTitle(original: server.title, date: date)
        let now = ISO8601DateFormatter().string(from: date)
        // A fresh basename for the copy; the sync POST drops a create op without a
        // non-empty relativePath, and reusing the server doc's path would collide
        // with `@@unique([folderId, relativePath])`.
        let relativePath = "\(newId).md"
        let document = Document(id: newId,
                                title: title,
                                content: server.content,
                                folderId: server.folderId,
                                isPublic: server.isPublic,
                                createdAt: now,
                                updatedAt: now,
                                relativePath: relativePath)
        let operation = SyncOperation(op: .create, type: .document,
                                      data: SyncOpData(id: newId,
                                                       folderId: server.folderId,
                                                       title: title,
                                                       content: server.content,
                                                       relativePath: relativePath,
                                                       isPublic: server.isPublic))
        return ConflictCopy(document: document, operation: operation)
    }

    /// `"<title> (conflicted copy <yyyy-MM-dd>)"`.
    static func conflictCopyTitle(original: String, date: Date) -> String {
        "\(original) (conflicted copy \(conflictDateString(date)))"
    }

    private static func conflictDateString(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        let year = c.year ?? 0
        let month = c.month ?? 0
        let day = c.day ?? 0
        return String(format: "%04d-%02d-%02d", year, month, day)
    }
}
