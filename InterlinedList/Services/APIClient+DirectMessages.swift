//
//  APIClient+DirectMessages.swift
//  InterlinedList
//

import Foundation

extension APIClient {
    /// The conversation-grouped inbox: one row per correspondent, newest activity
    /// first, each with its own unread count.
    ///
    /// Inbox-shaped only — Sent and Deleted stay on the flat `/api/dm` list, which
    /// is per-message by design. Paging is keyset, not offset: pass back the
    /// `nextCursor` the server returned, unmodified.
    func dmConversations(cursor: String? = nil, take: Int? = nil) async throws -> DMConversationPage {
        var query: [String] = []
        if let cursor, !cursor.isEmpty {
            query.append("cursor=" + queryValue(cursor))
        }
        if let take {
            query.append("take=\(take)")
        }
        let suffix = query.isEmpty ? "" : "?" + query.joined(separator: "&")
        return try await get("/api/dm/conversations" + suffix)
    }
}
