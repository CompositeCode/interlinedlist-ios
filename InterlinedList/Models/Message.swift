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

    var authorDisplay: String {
        guard let user = user else { return "Unknown" }
        let name = user.displayName?.isEmpty == false ? (user.displayName ?? user.username) : user.username
        return name
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
}

struct CreateMessageResponse: Codable {
    let message: String?
    let data: Message?
}
