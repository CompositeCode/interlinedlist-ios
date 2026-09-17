//
//  DMConversation.swift
//  InterlinedList
//

import Foundation

/// One row of the conversation-grouped inbox (`GET /api/dm/conversations`) — one
/// entry per correspondent rather than per message, with that conversation's own
/// unread count.
///
/// Identified by `pairKey`, which is the server's stable per-conversation key, so
/// a row keeps its identity as new messages arrive.
struct DMConversation: Codable, Identifiable, Hashable {
    let pairKey: String
    let otherUser: DMUser
    let lastMessageId: String
    let lastBody: String?
    /// Server-rendered preview: markdown stripped, or `[image]` for an image-only
    /// message. Prefer this over `lastBody` so the row matches the web.
    let preview: String?
    let lastImageUrls: [String]?
    let lastCreatedAt: String
    /// True when the last message in the conversation was sent by this account.
    let isMine: Bool
    let unreadCount: Int

    var id: String { pairKey }

    /// Matches the web's cap (`ConversationList.tsx`).
    var unreadBadge: String? {
        guard unreadCount > 0 else { return nil }
        return unreadCount > 99 ? "99+" : String(unreadCount)
    }

    var previewText: String {
        if let preview, !preview.isEmpty { return preview }
        if let lastBody, !lastBody.isEmpty { return lastBody }
        return (lastImageUrls?.isEmpty == false) ? "[image]" : ""
    }
}

/// Keyset page. `nextCursor` is an opaque base64 token — never parse or build it
/// client-side; pass back exactly what the server sent.
struct DMConversationPage: Codable {
    let items: [DMConversation]
    let nextCursor: String?
}
