//
//  ILWebURL.swift
//  InterlinedList
//

import Foundation

/// Builds canonical `interlinedlist.com` web permalinks for shareable content.
/// These are the public web URLs a user can paste anywhere; they are distinct from
/// the app's internal share-link tokens. Path shapes mirror the backend routes:
/// profile `/user/<username>`, message `/message/<id>`, list `/lists/<id>`,
/// document `/documents/<id>`.
enum ILWebURL {
    static let base = "https://interlinedlist.com"

    static func profile(_ username: String) -> URL? {
        make("/user", username)
    }

    static func message(_ id: String) -> URL? {
        make("/message", id)
    }

    static func list(_ id: String) -> URL? {
        make("/lists", id)
    }

    static func document(_ id: String) -> URL? {
        make("/documents", id)
    }

    private static func make(_ prefix: String, _ segment: String) -> URL? {
        guard !segment.isEmpty,
              let encoded = segment.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            return nil
        }
        return URL(string: base + prefix + "/" + encoded)
    }
}
