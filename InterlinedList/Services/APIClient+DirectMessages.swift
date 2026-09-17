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
            query.append("cursor=" + Self.encodedQueryValue(cursor))
        }
        if let take {
            query.append("take=\(take)")
        }
        let suffix = query.isEmpty ? "" : "?" + query.joined(separator: "&")
        return try await get("/api/dm/conversations" + suffix)
    }

    /// `.urlQueryAllowed` permits `+`, `=`, `&` and `/`, all of which appear in the
    /// base64 keyset cursor this route issues. Left unescaped, a `+` decodes as a
    /// space server-side and the cursor silently stops matching — the page repeats
    /// or ends early. Escape them explicitly.
    static func encodedQueryValue(_ raw: String) -> String {
        let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "+&=?#/"))
        return raw.addingPercentEncoding(withAllowedCharacters: allowed) ?? raw
    }
}
