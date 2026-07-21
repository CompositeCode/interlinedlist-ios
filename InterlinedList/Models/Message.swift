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

/// A single resolved link preview from POST /api/messages/:id/metadata.
struct MessageLinkPreview: Codable, Identifiable {
    let url: String
    let title: String?
    let description: String?
    let image: String?

    var id: String { url }
}

/// One destination a message was actually cross-posted to, echoed back on the
/// Message after it publishes (server field: `crossPostUrls`). The shape differs
/// per platform — Mastodon carries `statusId`/`instanceUrl`, Bluesky carries
/// `cid`/`uri` — so everything past `platform` is optional. This is the API's
/// source of truth for "where did this go", distinct from the compose-time
/// `crossPostResults` toast shape (which not every deployment returns).
struct CrossPostUrl: Codable, Identifiable, Equatable {
    let platform: String
    let url: String?
    let instanceName: String?
    let instanceUrl: String?
    let statusId: String?
    let cid: String?
    let uri: String?

    var id: String { url ?? uri ?? statusId ?? cid ?? platform }

    /// Human label for the destination, e.g. "techhub.social" or "Bluesky".
    var destinationName: String {
        if let instanceName, !instanceName.isEmpty { return instanceName }
        return platform.capitalized
    }
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
    let crossPostUrls: [CrossPostUrl]?

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

/// A single cross-post target on LinkedIn (personal profile or an organization page).
struct LinkedInTarget: Codable, Equatable {
    let kind: String          // "personal" | "organization"
    let organizationId: String?

    init(kind: String, organizationId: String? = nil) {
        self.kind = kind
        self.organizationId = organizationId
    }
}

/// Cross-post configuration carried on a scheduled message (PATCH /api/messages/:id).
struct ScheduledCrossPostConfig: Codable, Equatable {
    var mastodonProviderIds: [String]?
    var crossPostToBluesky: Bool?
    var crossPostToLinkedIn: Bool?
    var linkedInLinkAsFirstComment: Bool?
    var linkedInTargets: [LinkedInTarget]?
    var crossPostToTwitter: Bool?

    var isEmpty: Bool {
        (mastodonProviderIds?.isEmpty ?? true)
            && crossPostToBluesky != true
            && crossPostToLinkedIn != true
            && crossPostToTwitter != true
    }
}

struct CreateMessageBody: Encodable {
    let content: String
    let publiclyVisible: Bool?
    let parentId: String?
    let tags: [String]?
    let scheduledAt: String?
    let imageUrls: [String]?
    let videoUrls: [String]?
    // Repost / push
    var pushedMessageId: String?
    // Cross-posting (subscriber-only; omitted entirely for free users)
    var mastodonProviderIds: [String]?
    var crossPostToBluesky: Bool?
    var crossPostToLinkedIn: Bool?
    var linkedInTargets: [LinkedInTarget]?
    var linkedInLinkAsFirstComment: Bool?
    var crossPostToTwitter: Bool?
    var scheduledCrossPostConfig: ScheduledCrossPostConfig?
    var organizationId: String?
}

/// One platform's result after a cross-post attempt. Surfaced in a post-publish toast.
/// Best-effort: the create response may or may not include this depending on deployment.
/// All fields are optional because the server shape is inconsistent across deployments.
struct CrossPostResult: Codable, Identifiable {
    let platform: String?
    let success: Bool?
    let error: String?

    var id: String { platform ?? error ?? UUID().uuidString }
}

/// Builds the one-line "where did this go" summary shown in the post-confirmation
/// dialog. `crossPostUrls` is the reliable source of destination *names*; some
/// deployments return `crossPostResults` with `platform == nil`, which is why a
/// results-only summary can degrade to a nameless "Cross-post ✓". We therefore
/// prefer the URLs, then append any explicit failures the results array reports.
enum CrossPostSummary {
    static func line(urls: [CrossPostUrl], results: [CrossPostResult]) -> String? {
        if !urls.isEmpty {
            var parts = urls.map { "\($0.destinationName) ✓" }
            parts.append(contentsOf: failureParts(from: results))
            return parts.joined(separator: " · ")
        }
        let parts = results.map { resultPart(from: $0) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private static func failureParts(from results: [CrossPostResult]) -> [String] {
        results.filter { $0.success == false }.map { resultPart(from: $0) }
    }

    private static func resultPart(from result: CrossPostResult) -> String {
        let succeeded = result.success ?? false
        let label = result.platform?.capitalized ?? "Cross-post"
        let status = succeeded ? "✓" : "✗"
        if !succeeded, let msg = result.error, !msg.isEmpty {
            return "\(label) \(status) (\(msg))"
        }
        return "\(label) \(status)"
    }
}

struct CreateMessageResponse: Codable {
    let message: String?
    let data: Message?
    let crossPostResults: [CrossPostResult]?
}
