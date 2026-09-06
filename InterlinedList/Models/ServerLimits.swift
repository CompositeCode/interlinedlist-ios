//
//  ServerLimits.swift
//  InterlinedList
//

import CoreGraphics
import Foundation

/// The upload and content caps the backend enforces, from `GET /api/limits`
/// (public, no auth). Reading them rather than hardcoding matters most for
/// images: the server resizes every upload to `image.maxPixels` per side
/// regardless of what the client sends, so anything larger is wasted bytes on
/// the wire and a slower post.
struct ServerLimits: Codable, Equatable, Sendable {
    let media: Media
    let message: MessageLimits?

    struct Media: Codable, Equatable, Sendable {
        let image: ImageLimits
        let video: VideoLimits?
    }

    struct ImageLimits: Codable, Equatable, Sendable {
        let maxBytes: Int
        let maxPixels: Int
        let acceptedFormats: [String]?
    }

    struct VideoLimits: Codable, Equatable, Sendable {
        let maxBytes: Int
        let acceptedFormats: [String]?
    }

    struct MessageLimits: Codable, Equatable, Sendable {
        let maxContentLength: Int?
    }

    /// Used until `GET /api/limits` answers, and if it never does. These are the
    /// values the deployed backend reports today, so a failed fetch costs
    /// accuracy only if the server's caps change.
    static let fallback = ServerLimits(
        media: Media(
            image: ImageLimits(maxBytes: 1_400_000, maxPixels: 1200, acceptedFormats: nil),
            video: VideoLimits(maxBytes: 3_145_728, acceptedFormats: nil)
        ),
        message: MessageLimits(maxContentLength: 5000)
    )
}

/// The subset `ImageUploadProcessor` needs, in the units it works in.
struct ImageUploadLimits: Equatable, Sendable {
    let maxUploadBytes: Int
    let maxPixels: CGFloat

    init(maxUploadBytes: Int, maxPixels: CGFloat) {
        self.maxUploadBytes = maxUploadBytes
        self.maxPixels = maxPixels
    }

    init(_ limits: ServerLimits) {
        self.init(maxUploadBytes: limits.media.image.maxBytes,
                  maxPixels: CGFloat(limits.media.image.maxPixels))
    }

    static let fallback = ImageUploadLimits(ServerLimits.fallback)
}
