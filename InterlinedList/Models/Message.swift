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

extension LinkMetadataItem {
    /// Rebuilds the feed row's nested preview shape from the flat previews the
    /// metadata refresh returns, so a just-published message can render its card
    /// without waiting for the next feed fetch.
    ///
    /// `metadata` stays nil when a preview resolved to nothing renderable: the feed
    /// card is drawn only for a non-nil `metadata` (`LinkPreviewBlock`), so an
    /// all-nil content object would draw an empty box. The item itself is kept,
    /// because its `url` is what the rest of the app reads off a link.
    ///
    /// `platform` and `fetchStatus` stay nil rather than being guessed: the flat
    /// preview carries neither, and nothing renders off them.
    init(preview: MessageLinkPreview) {
        let title = Self.trimmedNonEmpty(preview.title)
        let description = Self.trimmedNonEmpty(preview.description)
        let thumbnail = Self.trimmedNonEmpty(preview.image)
        let content: LinkMetadataItemContent? =
            title == nil && description == nil && thumbnail == nil
            ? nil
            : LinkMetadataItemContent(thumbnail: thumbnail, title: title,
                                      description: description, text: nil, type: nil)
        self.init(url: preview.url, platform: nil, metadata: content, fetchStatus: nil)
    }

    static func from(previews: [MessageLinkPreview]) -> [LinkMetadataItem] {
        previews.map(LinkMetadataItem.init(preview:))
    }

    private static func trimmedNonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }
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
    /// The only mutable field on the row: the metadata refresh that follows a
    /// publish backfills it in place on the already-inserted feed message.
    var linkMetadata: LinkMetadata?
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

// Identity-based conformance so a Message can drive `navigationDestination(item:)`.
// The `id` uniquely identifies a message; the nested link/cross-post/user payloads
// are not (and need not be) Hashable.
extension Message: Hashable {
    static func == (lhs: Message, rhs: Message) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
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

/// A single cross-post destination on LinkedIn, encoded as the backend's
/// discriminated union (`resolve-linkedin-target.ts`):
///   { kind: "personal" }
///   { kind: "orgPage", pageId }           // pageId = OrgLinkedInPage.id (uuid)
///   { kind: "personalPage", personalPageId } // personalPageId = LinkedInPersonalPage.id (uuid)
/// Nil page ids are omitted from the encoded body so `personal` sends only `kind`.
struct LinkedInTarget: Codable, Equatable {
    let kind: String
    let pageId: String?
    let personalPageId: String?

    init(kind: String, pageId: String? = nil, personalPageId: String? = nil) {
        self.kind = kind
        self.pageId = pageId
        self.personalPageId = personalPageId
    }

    static func personal() -> LinkedInTarget { LinkedInTarget(kind: "personal") }
    static func orgPage(pageId: String) -> LinkedInTarget { LinkedInTarget(kind: "orgPage", pageId: pageId) }
    static func personalPage(personalPageId: String) -> LinkedInTarget {
        LinkedInTarget(kind: "personalPage", personalPageId: personalPageId)
    }

    private enum CodingKeys: String, CodingKey {
        case kind, pageId, personalPageId
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encodeIfPresent(pageId, forKey: .pageId)
        try container.encodeIfPresent(personalPageId, forKey: .personalPageId)
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

/// One platform's cross-post reply count, from `POST /api/messages/{id}/reply-counts`.
/// The server caches for 10 minutes and backs unsupported platforms off for 24 hours,
/// so the client never retries on its own.
struct ReplyCountEntry: Codable, Identifiable {
    let platform: String
    let count: Int?
    /// `success`, `unsupported` or `error`. Only `success` entries are worth drawing.
    let status: String
    let checkedAt: String?

    var id: String { platform }

    var isDisplayable: Bool { status == "success" && count != nil }
}

struct ReplyCountsResponse: Codable {
    let replyCounts: [ReplyCountEntry]
    let repliesCheckedAt: String?
}
