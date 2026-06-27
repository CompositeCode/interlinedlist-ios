//
//  NotificationPreference.swift
//  InterlinedList
//

import Foundation

/// Per-channel toggles for a notification event. The backend exposes only the
/// channels that actually exist for a given event (GAP §B3): `push` and `inApp`
/// (there is no `email` channel). Render UI rows from the keys that are present
/// rather than assuming a fixed grid.
struct NotificationChannels: Codable, Equatable {
    var push: Bool?
    var inApp: Bool?
}

/// One notification event the server can emit, with its supported channels.
/// Authoritative catalog today: `dig`, `push`, `follow` (follow is push-only).
struct NotificationPreference: Identifiable, Codable, Equatable {
    let key: String
    let label: String
    let description: String?
    var channels: NotificationChannels

    var id: String { key }

    var supportsPush: Bool { channels.push != nil }
    var supportsInApp: Bool { channels.inApp != nil }
}

struct NotificationPreferencesResponse: Codable {
    let events: [NotificationPreference]
}

/// PATCH body — updates the channel toggles for a single event.
struct NotificationPreferenceUpdate: Encodable {
    let key: String
    let channels: NotificationChannels
}
