//
//  Moderation.swift
//  InterlinedList
//

import Foundation

enum ReportReason: String, CaseIterable, Identifiable {
    case spam
    case harassment
    case misinformation
    case inappropriate
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .spam: return "Spam"
        case .harassment: return "Harassment"
        case .misinformation: return "Misinformation"
        case .inappropriate: return "Inappropriate content"
        case .other: return "Other"
        }
    }
}

struct BlockedUser: Identifiable, Decodable {
    let id: String
    let username: String
    let displayName: String?
    let avatar: String?
}

struct BlockedUsersResponse: Decodable {
    let blockedUsers: [BlockedUser]
    let pagination: Pagination?
}

struct MutedUser: Identifiable, Decodable {
    let id: String
    let username: String
    let displayName: String?
    let avatar: String?
}

struct MutedUsersResponse: Decodable {
    let mutedUsers: [MutedUser]
    let pagination: Pagination?
}
