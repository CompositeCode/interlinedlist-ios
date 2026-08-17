//
//  LinkedInPostingTarget.swift
//  InterlinedList
//

import Foundation

/// One selectable LinkedIn destination returned by GET /api/linkedin/posting-targets.
/// Distinct from `LinkedInTarget` (the compact union sent in a post body): this is the
/// display-oriented option carrying a label/avatar and an `enabled` flag.
struct LinkedInPostingTarget: Codable, Identifiable, Equatable {
    let kind: String
    let label: String
    let avatarUrl: String?
    let pageId: String?
    let personalPageId: String?
    let linkedInPageId: String?
    let enabled: Bool

    var id: String { pageId ?? personalPageId ?? kind }

    /// Maps this option to the compact posting union sent in a message body.
    var asTarget: LinkedInTarget {
        switch kind {
        case "orgPage":
            if let pageId { return .orgPage(pageId: pageId) }
            return .personal()
        case "personalPage":
            if let personalPageId { return .personalPage(personalPageId: personalPageId) }
            return .personal()
        default:
            return .personal()
        }
    }
}

/// Wrapper for the posting-targets endpoint response.
struct LinkedInPostingTargetsResponse: Codable {
    let targets: [LinkedInPostingTarget]?
    let orgScopeMissing: Bool?
}
