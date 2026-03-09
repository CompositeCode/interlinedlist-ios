//
//  User.swift
//  InterlinedList
//

import Foundation

struct User: Codable, Identifiable {
    let id: String
    let email: String
    let username: String
    let displayName: String?
    let avatar: String?
    let bio: String?
    let theme: String?
    let emailVerified: Bool?
    let createdAt: String?

    var displayNameOrUsername: String {
        displayName?.isEmpty == false ? (displayName ?? username) : username
    }
}

struct UserResponse: Codable {
    let user: User
}
