//
//  Message.swift
//  InterlinedList
//

import Foundation

struct MessageUser: Codable {
    let id: String
    let username: String
    let displayName: String?
    let avatar: String?
}

/// Link preview metadata for one URL in a message.
struct LinkMetadataItem: Codable {
    let url: String
    let platform: String?
    let metadata: LinkMetadataItemContent?
    let fetchStatus: String?
}

struct LinkMetadataItemContent: Codable {
    let thumbnail: String?
    let title: String?
    let description: String?
    let text: String?
    let type: String?
}

struct LinkMetadata: Codable {
    let links: [LinkMetadataItem]
}

struct Message: Codable, Identifiable {
    let id: String
    let content: String
    let publiclyVisible: Bool?
    let userId: String
    let createdAt: String
    let updatedAt: String?
    let user: MessageUser?
    let imageUrls: [String]?
    let videoUrls: [String]?
    let linkMetadata: LinkMetadata?
    let parentId: String?
    let scheduledAt: String?
    let tags: [String]?
    let digCount: Int?
    let dugByMe: Bool?

    var authorDisplay: String {
        guard let user = user else { return "Unknown" }
        let name = user.displayName?.isEmpty == false ? (user.displayName ?? user.username) : user.username
        return name
    }

    var hasPreviews: Bool {
        let hasLinks = linkMetadata?.links.isEmpty == false
        let hasImages = imageUrls?.isEmpty == false
        let hasVideos = videoUrls?.isEmpty == false
        return hasLinks || hasImages || hasVideos
    }
}

struct MessagesResponse: Codable {
    let messages: [Message]
    let pagination: Pagination?
}

struct Pagination: Codable {
    let total: Int
    let limit: Int
    let offset: Int
    let hasMore: Bool
}

struct CreateMessageBody: Encodable {
    let content: String
    let publiclyVisible: Bool?
    let parentId: String?
    let tags: [String]?
    let scheduledAt: String?
    let imageUrls: [String]?
}

struct CreateMessageResponse: Codable {
    let message: String?
    let data: Message?
}
