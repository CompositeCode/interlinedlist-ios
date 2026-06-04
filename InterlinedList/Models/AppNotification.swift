//
//  AppNotification.swift
//  InterlinedList
//

import Foundation

struct AppNotification: Identifiable, Codable {
    let id: String
    let message: String?
    let type: String?
    let read: Bool?
    let createdAt: String?
    let actorUsername: String?
}

struct NotificationsResponse: Codable {
    let unreadCount: Int
    let items: [AppNotification]
}
