//
//  AppSettingsSync.swift
//  InterlinedList
//

import Foundation

/// The app's key in the settings-sync service. Contract:
/// https://interlinedlist.com/help/api/app-settings
enum AppSettingsKey {
    static let appKey = "il-ios"
    static let platform = "ios"
    /// Bump when the meaning of a stored field changes so an older client can tell.
    static let schemaVersion = 1
    /// Server cap (`MAX_SETTINGS_BYTES`). Enforced client-side too — a write above
    /// it is a 413, which is a bug in what we chose to store, not a transient error.
    static let maxSettingsBytes = 64 * 1024
}

/// The account-level (shared) settings iOS syncs. Deliberately small: preferences a
/// second device should inherit, never cached content.
///
/// Anything phone-specific (per-device UI state, local-only toggles) belongs in the
/// per-device document instead, which is why this type carries none of it.
struct AppSharedSettings: Codable, Equatable {
    var theme: String?
    var defaultPubliclyVisible: Bool?
    var showAdvancedPostSettings: Bool?
    var viewingPreference: String?
    var messagesPerPage: Int?
    var showPreviews: Bool?
    var notificationTrayLimit: Int?

    static let empty = AppSharedSettings()
}

/// One settings document as the service stores it. `settings` is an opaque blob the
/// server round-trips byte-for-byte, so it is modelled generically.
struct SettingsDoc<Settings: Codable>: Codable {
    let appKey: String
    let scope: String?
    let deviceId: String?
    let version: Int
    let updatedAt: String?
    let schemaVersion: Int?
    let settings: Settings
}

/// `GET …/bootstrap` — where a fresh install should start from.
struct SettingsBootstrap<Settings: Codable>: Codable {
    let source: String
    let version: Int?
    let schemaVersion: Int?
    let settings: Settings?
    let defaultDeviceId: String?
    let defaultDeviceName: String?
}

struct AppDevice: Codable, Identifiable {
    let deviceId: String
    let deviceName: String?
    let platform: String?
    let isDefault: Bool?
    let lastSeenAt: String?
    let appVersion: String?
    let osVersion: String?

    var id: String { deviceId }
}

struct AppDevicesResponse: Codable {
    let devices: [AppDevice]
}

struct AppDeviceResponse: Codable {
    let device: AppDevice
}

/// Raised when the server rejects a write because someone else wrote first. The
/// caller must re-read and re-apply — last-write-wins is wrong here, and the server
/// hands back the winning document so no extra round trip is needed.
struct SettingsVersionConflict<Settings: Codable>: Error {
    let current: SettingsDoc<Settings>?
}
