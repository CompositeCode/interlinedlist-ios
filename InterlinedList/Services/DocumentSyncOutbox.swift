//
//  DocumentSyncOutbox.swift
//  InterlinedList
//

import Foundation

/// Pure, deterministic queue logic for the offline document write path. No I/O.
/// Enqueues create/update/delete ops into a `DocumentSyncState.outbox`, coalescing
/// repeated edits to the same id so the outbox stays a minimal per-id intent:
///
/// - **create → update…** collapse to a single **create** carrying the latest fields
///   (the row was never on the server, so it should arrive as one create).
/// - **update → update…** collapse to a single **update** carrying the latest fields.
/// - **delete of a not-yet-synced create** cancels **both** (the row never reached
///   the server, so nothing needs to be pushed).
/// - **delete of a synced/updated row** collapses any queued create/update for that
///   id into a single **delete**.
///
/// `localStates` tracks whether each id is `.dirty` (un-pushed create/update) or
/// `.deleted`. `clearOutbox` marks pushed dirties `.synced`, drops deletes, and
/// empties the queue after a successful `POST /sync`.
enum DocumentSyncOutbox {

    // MARK: - Enqueue

    static func enqueue(_ op: SyncOperation, into state: inout DocumentSyncState) {
        let id = op.data.id
        switch op.op {
        case .create:
            replaceOrAppend(op, id: id, into: &state)
            state.localStates[id] = .dirty
        case .update:
            enqueueUpdate(op, id: id, into: &state)
        case .delete:
            enqueueDelete(op, id: id, into: &state)
        }
    }

    private static func enqueueUpdate(_ op: SyncOperation, id: String, into state: inout DocumentSyncState) {
        if let existing = firstOp(for: id, in: state), existing.op == .create {
            // A pending create absorbs the update: push it as a single create with
            // the merged (latest) fields.
            let merged = SyncOperation(op: .create, type: op.type, path: op.path ?? existing.path,
                                       data: merge(existing.data, into: op.data))
            replaceOrAppend(merged, id: id, into: &state)
        } else if let existing = firstOp(for: id, in: state), existing.op == .update {
            let merged = SyncOperation(op: .update, type: op.type, path: op.path ?? existing.path,
                                       data: merge(existing.data, into: op.data))
            replaceOrAppend(merged, id: id, into: &state)
        } else {
            replaceOrAppend(op, id: id, into: &state)
        }
        state.localStates[id] = .dirty
    }

    private static func enqueueDelete(_ op: SyncOperation, id: String, into state: inout DocumentSyncState) {
        if let existing = firstOp(for: id, in: state), existing.op == .create {
            // The row never reached the server — cancel both create and delete.
            state.outbox.removeAll { $0.data.id == id }
            state.localStates[id] = nil
            return
        }
        // Drop any queued create/update; the delete supersedes them.
        replaceOrAppend(op, id: id, into: &state)
        state.localStates[id] = .deleted
    }

    // MARK: - Push payload

    /// The `[SyncOperation]` to POST. This is just the current outbox — ops are
    /// already coalesced to one-per-id on enqueue.
    static func pushPayload(from state: DocumentSyncState) -> [SyncOperation] {
        state.outbox
    }

    // MARK: - Clear after a successful push

    /// Called after a `200` from `POST /sync`. Drops the pushed ops and settles
    /// local states: dirties become `.synced`, deletes are forgotten (the row is
    /// already gone locally).
    static func clearOutbox(_ pushed: [SyncOperation], from state: inout DocumentSyncState) {
        let pushedIds = Set(pushed.map { $0.data.id })
        for op in pushed {
            switch op.op {
            case .create, .update:
                state.localStates[op.data.id] = .synced
            case .delete:
                state.localStates[op.data.id] = nil
            }
        }
        state.outbox.removeAll { pushedIds.contains($0.data.id) }
    }

    // MARK: - Helpers

    private static func firstOp(for id: String, in state: DocumentSyncState) -> SyncOperation? {
        state.outbox.first { $0.data.id == id }
    }

    private static func replaceOrAppend(_ op: SyncOperation, id: String, into state: inout DocumentSyncState) {
        if let idx = state.outbox.firstIndex(where: { $0.data.id == id }) {
            state.outbox[idx] = op
        } else {
            state.outbox.append(op)
        }
    }

    /// Overlays `newer`'s non-nil fields onto `older`, so a coalesced op carries
    /// the latest value of each field the user has touched.
    private static func merge(_ older: SyncOpData, into newer: SyncOpData) -> SyncOpData {
        SyncOpData(
            id: newer.id,
            folderId: newer.folderId ?? older.folderId,
            parentId: newer.parentId ?? older.parentId,
            name: newer.name ?? older.name,
            title: newer.title ?? older.title,
            content: newer.content ?? older.content,
            relativePath: newer.relativePath ?? older.relativePath,
            isPublic: newer.isPublic ?? older.isPublic
        )
    }
}
