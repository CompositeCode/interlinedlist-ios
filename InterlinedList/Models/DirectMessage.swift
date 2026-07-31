//
//  DirectMessage.swift
//  InterlinedList
//

import Foundation

/// A user you can direct-message (mutual-follow set). Same shape as `MessageUser`
/// but kept distinct so the DM surface can evolve independently.
struct DMUser: Codable, Identifiable, Hashable {
    let id: String
    let username: String
    let displayName: String?
    let avatar: String?

    var displayNameOrUsername: String {
        displayName?.isEmpty == false ? (displayName ?? username) : username
    }
}

/// A single direct message. `sender`/`recipient` may be absent on some payloads
/// (e.g. thread updates), so both are optional and the view falls back to ids.
struct DMMessage: Codable, Identifiable, Hashable {
    let id: String
    let pairKey: String?
    let senderId: String
    let recipientId: String
    let body: String
    let imageUrls: [String]
    let createdAt: String
    let readAt: String?
    let sender: DMUser?
    let recipient: DMUser?
    let preview: String?

    enum CodingKeys: String, CodingKey {
        case id, pairKey, senderId, recipientId, body, imageUrls, createdAt, readAt, sender, recipient, preview
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        pairKey = try c.decodeIfPresent(String.self, forKey: .pairKey)
        senderId = try c.decode(String.self, forKey: .senderId)
        recipientId = try c.decode(String.self, forKey: .recipientId)
        body = try c.decodeIfPresent(String.self, forKey: .body) ?? ""
        imageUrls = try c.decodeIfPresent([String].self, forKey: .imageUrls) ?? []
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
        readAt = try c.decodeIfPresent(String.self, forKey: .readAt)
        sender = try c.decodeIfPresent(DMUser.self, forKey: .sender)
        recipient = try c.decodeIfPresent(DMUser.self, forKey: .recipient)
        preview = try c.decodeIfPresent(String.self, forKey: .preview)
    }

    init(
        id: String,
        pairKey: String? = nil,
        senderId: String,
        recipientId: String,
        body: String,
        imageUrls: [String] = [],
        createdAt: String,
        readAt: String? = nil,
        sender: DMUser? = nil,
        recipient: DMUser? = nil,
        preview: String? = nil
    ) {
        self.id = id
        self.pairKey = pairKey
        self.senderId = senderId
        self.recipientId = recipientId
        self.body = body
        self.imageUrls = imageUrls
        self.createdAt = createdAt
        self.readAt = readAt
        self.sender = sender
        self.recipient = recipient
        self.preview = preview
    }

    var isRead: Bool { readAt != nil }

    /// The other party relative to `userId` (nil if that side isn't populated).
    func otherParty(selfId: String?) -> DMUser? {
        guard let selfId else { return sender ?? recipient }
        return senderId == selfId ? recipient : sender
    }
}

/// A conversation with one other user, returned by `GET /api/dm/thread/:username`.
struct DMThread: Codable {
    let items: [DMMessage]
    let olderCursor: String?
    let isMutual: Bool
    let isBlocked: Bool
    let otherUser: DMUser

    enum CodingKeys: String, CodingKey {
        case items, olderCursor, isMutual, isBlocked, otherUser
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = try c.decodeIfPresent([DMMessage].self, forKey: .items) ?? []
        olderCursor = try c.decodeIfPresent(String.self, forKey: .olderCursor)
        isMutual = try c.decodeIfPresent(Bool.self, forKey: .isMutual) ?? false
        isBlocked = try c.decodeIfPresent(Bool.self, forKey: .isBlocked) ?? false
        otherUser = try c.decode(DMUser.self, forKey: .otherUser)
    }

    init(items: [DMMessage], olderCursor: String?, isMutual: Bool, isBlocked: Bool, otherUser: DMUser) {
        self.items = items
        self.olderCursor = olderCursor
        self.isMutual = isMutual
        self.isBlocked = isBlocked
        self.otherUser = otherUser
    }
}

/// One inbox/sent/deleted folder in the DM surface.
enum DMFolder: String, CaseIterable, Identifiable {
    case inbox
    case sent
    case deleted

    var id: String { rawValue }

    var title: String {
        switch self {
        case .inbox: return "Inbox"
        case .sent: return "Sent"
        case .deleted: return "Deleted"
        }
    }
}

// MARK: - Response wrappers

struct DMListResponse: Codable {
    let items: [DMMessage]
    let nextCursor: String?

    enum CodingKeys: String, CodingKey { case items, nextCursor }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = try c.decodeIfPresent([DMMessage].self, forKey: .items) ?? []
        nextCursor = try c.decodeIfPresent(String.self, forKey: .nextCursor)
    }

    init(items: [DMMessage], nextCursor: String?) {
        self.items = items
        self.nextCursor = nextCursor
    }
}

struct DMMessageResponse: Codable {
    let message: DMMessage
}

struct DMRecipientsResponse: Codable {
    let recipients: [DMUser]

    enum CodingKeys: String, CodingKey { case recipients }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        recipients = try c.decodeIfPresent([DMUser].self, forKey: .recipients) ?? []
    }

    init(recipients: [DMUser]) { self.recipients = recipients }
}

struct DMUnreadCountResponse: Codable {
    let count: Int
}

struct DMUpdatedResponse: Codable {
    let updated: Int
}
