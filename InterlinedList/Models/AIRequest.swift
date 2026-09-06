//
//  AIRequest.swift
//  InterlinedList
//

import Foundation

/// `context` on `POST /api/ai/suggest`. Every field is optional and only the
/// ones a feature reads are sent; the server clamps or ignores the rest.
struct AIContext: Encodable, Equatable {
    /// Powered Template: which base template to personalize.
    var templateKey: String?
    /// Powered Document mode.
    var mode: String?
    var listId: String?
    var documentId: String?
    var url: String?
    /// Writing Assistant action.
    var action: String?
    var targetPlatform: String?
    /// Series sizing hints (clamped server-side).
    var count: Int?
    var spacingMinutes: Int?
    /// Message Series: the composer's live cross-post channel labels, used
    /// server-side to size each generated message to the tightest service limit.
    var channels: [String]?

    static func writingAssist(_ action: AIWritingAction) -> AIContext {
        AIContext(action: action.rawValue)
    }

    static func poweredTemplate(templateKey: String?) -> AIContext {
        AIContext(templateKey: templateKey)
    }

    static func messageSeries(channels: [String], count: Int? = nil) -> AIContext {
        AIContext(count: count, channels: channels)
    }

    static func poweredDocument(mode: AIDocumentMode, listId: String? = nil,
                                documentId: String? = nil, url: String? = nil) -> AIContext {
        AIContext(mode: mode.rawValue, listId: listId, documentId: documentId, url: url)
    }
}

/// The composer's live cross-post selection, forwarded verbatim to
/// `/api/ai/generate` so a "schedule immediately" message series posts to exactly
/// the accounts the compose form has toggled on. Sanitized server-side against
/// the caller's own connected accounts.
struct AIComposerCrossPost: Encodable, Equatable {
    var crossPostToBluesky: Bool?
    var selectedMastodonIds: [String]?
    var crossPostToTwitter: Bool?
    var crossPostToLinkedIn: Bool?
    var selectedLinkedInTargets: [LinkedInTarget]?
    var linkedInLinkAsFirstComment: Bool?

    var isEmpty: Bool {
        crossPostToBluesky != true
            && crossPostToTwitter != true
            && crossPostToLinkedIn != true
            && (selectedMastodonIds?.isEmpty ?? true)
    }

    /// The `messages_campaign` channel labels this selection implies. Mirrors the
    /// server's `channelLabelsFromSelection` so the sizing note the user reads
    /// matches the limit the model is actually given.
    var channelLabels: [String] {
        var labels: [String] = []
        if crossPostToBluesky == true { labels.append("Bluesky") }
        if let ids = selectedMastodonIds, !ids.isEmpty { labels.append("Mastodon") }
        if crossPostToLinkedIn == true { labels.append("LinkedIn") }
        if crossPostToTwitter == true { labels.append("X/Twitter") }
        return labels
    }
}

/// Per-service post character limits, mirroring `lib/crosspost/char-limits.ts`.
/// Drives the "sized to fit N characters" note on the Message Series preview.
enum AICrossPostLimits {
    static let bluesky = 300
    static let mastodon = 500
    static let linkedIn = 3000
    static let twitter = 280

    private static func limit(forLabel label: String) -> Int? {
        switch label.trimmingCharacters(in: .whitespaces).lowercased() {
        case "bluesky": return bluesky
        case "mastodon": return mastodon
        case "linkedin": return linkedIn
        case "x/twitter", "x", "twitter": return twitter
        default: return nil
        }
    }

    /// The tightest limit across the selected channels, or `fallback` when none
    /// of them maps to a message cross-post channel.
    static func minCharLimit(labels: [String], fallback: Int) -> Int {
        let limits = labels.compactMap(limit(forLabel:))
        return limits.min() ?? fallback
    }
}
