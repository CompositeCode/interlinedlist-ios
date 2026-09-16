//
//  FeedMerge.swift
//  InterlinedList
//

import Foundation

/// Reconciles the store's feed page into a view's working copy of the feed.
///
/// The working copy is not a plain mirror of `AppDataStore.feedMessages`: pagination
/// appends pages the store never sees, so the store's page has to be merged into it
/// rather than replace it. Rows already held keep their position (and with it the
/// scroll position); a row the store has re-sent replaces the held copy in place, so
/// an edit to an existing row is visible without a reload.
enum FeedMerge {
    struct Result {
        let messages: [Message]
        /// Rows this merge inserted or replaced — the ones whose derived per-row
        /// state (dig counts) needs re-seeding. Empty means nothing moved.
        let changed: [Message]
    }

    static func merge(existing: [Message], incoming: [Message]) -> Result {
        let incomingById = Dictionary(incoming.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        var merged = existing
        var replaced: [Message] = []
        for index in merged.indices {
            guard let updated = incomingById[merged[index].id] else { continue }
            merged[index] = updated
            replaced.append(updated)
        }
        let existingIds = Set(existing.map(\.id))
        let inserted = incoming.filter { !existingIds.contains($0.id) }
        merged.insert(contentsOf: inserted, at: 0)
        return Result(messages: merged, changed: inserted + replaced)
    }
}
