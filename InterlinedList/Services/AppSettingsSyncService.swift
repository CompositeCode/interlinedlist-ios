//
//  AppSettingsSyncService.swift
//  InterlinedList
//

import Foundation
import UIKit

/// Keeps the account-level preferences in step across installs and devices via the
/// settings-sync service (`appKey = "il-ios"`).
///
/// **Account-level vs device-level.** Everything this service writes is
/// account-level: theme, posting defaults and the four view preferences — settings a
/// second device should inherit. Nothing phone-specific is written, and no cached
/// content ever is; the 64 KiB cap is a hard budget, not a target.
///
/// The server is the authority for these values (they also live on `User` via
/// `PATCH /api/user/update`); this document is what a *fresh install* reads before
/// it has a user, and what keeps two installs aligned.
@MainActor
final class AppSettingsSyncService: ObservableObject {
    @Published private(set) var lastSyncedVersion: Int?
    @Published private(set) var devices: [AppDevice] = []

    private let api: APIClient
    private var registeredDeviceId: String?

    init(api: APIClient = .shared) {
        self.api = api
    }

    // MARK: - Device registration

    /// Registers this install once per launch. The id comes from the Keychain and is
    /// generated once per install; if the keychain is unavailable we skip rather than
    /// mint a fresh id, which would register a new device on every launch.
    @discardableResult
    func registerDeviceIfNeeded() async -> String? {
        if let registeredDeviceId { return registeredDeviceId }
        guard let deviceId = KeychainService.deviceId() else { return nil }
        do {
            try await api.registerAppDevice(
                deviceId: deviceId,
                deviceName: UIDevice.current.name,
                appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
                osVersion: UIDevice.current.systemVersion
            )
            registeredDeviceId = deviceId
            return deviceId
        } catch {
            // Sync is a convenience; a failed registration must not block launch.
            return nil
        }
    }

    func loadDevices() async {
        devices = (try? await api.appDevices()) ?? []
    }

    func renameDevice(_ deviceId: String, to name: String) async throws {
        _ = try await api.renameAppDevice(deviceId: deviceId, deviceName: name)
        await loadDevices()
    }

    func forgetDevice(_ deviceId: String) async throws {
        try await api.forgetAppDevice(deviceId: deviceId)
        await loadDevices()
    }

    // MARK: - Reading

    /// What a fresh install should start from: the account document if there is one,
    /// otherwise whatever provenance `bootstrap` reports. Returns nil when the
    /// account has never synced.
    func loadSharedSettings() async -> AppSharedSettings? {
        if let doc: SettingsDoc<AppSharedSettings> = try? await api.appSettings() {
            lastSyncedVersion = doc.version
            return doc.settings
        }
        if let bootstrap: SettingsBootstrap<AppSharedSettings> = try? await api.appSettingsBootstrap() {
            lastSyncedVersion = bootstrap.version
            return bootstrap.settings
        }
        return nil
    }

    // MARK: - Writing

    /// Writes with compare-and-swap. On a conflict the winning document is re-read
    /// and the change re-applied on top — last-write-wins is wrong here, and the
    /// server tells us when it happened. One retry: a second conflict means another
    /// device is writing continuously, and spinning would make that worse.
    @discardableResult
    func save(_ settings: AppSharedSettings) async -> Bool {
        for attempt in 0..<2 {
            do {
                let doc = try await api.putAppSettings(settings, baseVersion: lastSyncedVersion ?? 0)
                lastSyncedVersion = doc.version
                return true
            } catch is SettingsVersionConflict<AppSharedSettings> {
                guard attempt == 0 else { return false }
                // Re-read to pick up the winner's version, then write again.
                _ = await loadSharedSettings()
            } catch {
                return false
            }
        }
        return false
    }

    /// The account-level projection of the current user. Kept in one place so the
    /// account/device split is explicit rather than implied by call sites.
    static func sharedSettings(from user: User) -> AppSharedSettings {
        AppSharedSettings(
            theme: user.theme,
            defaultPubliclyVisible: user.defaultPubliclyVisible,
            showAdvancedPostSettings: user.showAdvancedPostSettings,
            viewingPreference: user.viewingPreference,
            messagesPerPage: user.messagesPerPage,
            showPreviews: user.showPreviews,
            notificationTrayLimit: user.notificationTrayLimit
        )
    }
}
