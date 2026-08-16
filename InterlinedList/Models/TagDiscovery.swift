//
//  TagDiscovery.swift
//  InterlinedList
//

import Foundation

/// A trending tag from `GET /api/tags/trending` — a tag used on public messages,
/// with its occurrence count and most-recent use within the queried window.
/// Tags carry no leading `#` (matching the feed's `tag:` filter), so callers add
/// their own presentation prefix.
struct TrendingTag: Codable, Identifiable, Equatable {
    let tag: String
    let count: Int
    /// ISO-8601 timestamp of the most recent public message carrying this tag.
    /// Optional for decoding resilience; always present from the live endpoint.
    let lastUsedAt: String?

    var id: String { tag }
}

/// A single tag-autocomplete suggestion from `GET /api/tags/autocomplete`.
struct TagSuggestion: Codable, Identifiable, Equatable {
    let tag: String
    let count: Int

    var id: String { tag }
}
