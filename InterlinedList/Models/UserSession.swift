//
//  UserSession.swift
//  InterlinedList
//

import Foundation

struct UserSession: Identifiable, Decodable {
    let id: String
    let deviceLabel: String?
    let createdAt: String?
    let lastUsedAt: String?
    let isCurrent: Bool

    enum CodingKeys: String, CodingKey {
        case id, deviceLabel, createdAt, lastUsedAt, isCurrent
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        deviceLabel = try container.decodeIfPresent(String.self, forKey: .deviceLabel)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        lastUsedAt = try container.decodeIfPresent(String.self, forKey: .lastUsedAt)
        isCurrent = (try? container.decode(Bool.self, forKey: .isCurrent)) ?? false
    }

    init(id: String, deviceLabel: String?, createdAt: String?, lastUsedAt: String?, isCurrent: Bool) {
        self.id = id
        self.deviceLabel = deviceLabel
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
        self.isCurrent = isCurrent
    }
}

struct UserSessionsResponse: Decodable {
    let sessions: [UserSession]
}
