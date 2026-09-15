//
//  APIClient+AppSettings.swift
//  InterlinedList
//

import Foundation

/// CAS write envelope. File-scope because Swift cannot nest a generic type inside a
/// generic function.
private struct SettingsWriteBody<T: Codable>: Encodable {
    let baseVersion: Int
    let schemaVersion: Int
    let settings: T
}

extension APIClient {
    private var appSettingsBase: String {
        "/api/user/app-settings/\(pathSegment(AppSettingsKey.appKey))"
    }

    // MARK: - Account (shared) document

    /// The account-level document. `nil` when the account has none yet (404) — a
    /// fresh account, not an error.
    func appSettings<S: Codable>(_ type: S.Type = S.self) async throws -> SettingsDoc<S>? {
        do {
            return try await get(appSettingsBase)
        } catch let error as APIError where Self.isNotFound(error) {
            return nil
        }
    }

    /// Compare-and-swap write. `baseVersion` is the version this client last read;
    /// pass 0 for a first write. A `409` throws `SettingsVersionConflict` carrying
    /// the winning document, so the caller can re-apply without another round trip.
    @discardableResult
    func putAppSettings<S: Codable>(_ settings: S, baseVersion: Int) async throws -> SettingsDoc<S> {
        try assertWithinSizeCap(settings)
        let body = SettingsWriteBody(
            baseVersion: baseVersion,
            schemaVersion: AppSettingsKey.schemaVersion,
            settings: settings
        )
        do {
            return try await putCamel(appSettingsBase, body: body)
        } catch let error as APIError {
            if let conflict: SettingsVersionConflict<S> = Self.conflict(from: error) { throw conflict }
            throw error
        }
    }

    func deleteAppSettings() async throws {
        try await delete(appSettingsBase)
    }

    /// What a fresh install should start from. `nil` when there is no provenance yet.
    func appSettingsBootstrap<S: Codable>(_ type: S.Type = S.self) async throws -> SettingsBootstrap<S>? {
        do {
            return try await get(appSettingsBase + "/bootstrap")
        } catch let error as APIError where Self.isNotFound(error) {
            return nil
        }
    }

    // MARK: - Devices

    func appDevices() async throws -> [AppDevice] {
        let response: AppDevicesResponse = try await get(appSettingsBase + "/devices")
        return response.devices
    }

    @discardableResult
    func registerAppDevice(
        deviceId: String,
        deviceName: String,
        appVersion: String?,
        osVersion: String?
    ) async throws -> AppDevice {
        struct Body: Encodable {
            let deviceId: String
            let deviceName: String
            let platform: String
            let appVersion: String?
            let osVersion: String?
        }
        let response: AppDeviceResponse = try await postCamel(
            appSettingsBase + "/devices",
            body: Body(
                deviceId: deviceId,
                deviceName: deviceName,
                platform: AppSettingsKey.platform,
                appVersion: appVersion,
                osVersion: osVersion
            )
        )
        return response.device
    }

    @discardableResult
    func renameAppDevice(deviceId: String, deviceName: String) async throws -> AppDevice {
        struct Body: Encodable { let deviceName: String }
        let response: AppDeviceResponse = try await patchCamel(
            appSettingsBase + "/devices/" + pathSegment(deviceId),
            body: Body(deviceName: deviceName)
        )
        return response.device
    }

    func forgetAppDevice(deviceId: String) async throws {
        try await delete(appSettingsBase + "/devices/" + pathSegment(deviceId))
    }

    // MARK: - Per-device document

    func appDeviceSettings<S: Codable>(deviceId: String, _ type: S.Type = S.self) async throws -> SettingsDoc<S>? {
        do {
            return try await get(appSettingsBase + "/devices/" + pathSegment(deviceId) + "/settings")
        } catch let error as APIError where Self.isNotFound(error) {
            return nil
        }
    }

    @discardableResult
    func putAppDeviceSettings<S: Codable>(
        deviceId: String,
        settings: S,
        baseVersion: Int
    ) async throws -> SettingsDoc<S> {
        try assertWithinSizeCap(settings)
        let body = SettingsWriteBody(
            baseVersion: baseVersion,
            schemaVersion: AppSettingsKey.schemaVersion,
            settings: settings
        )
        do {
            return try await putCamel(
                appSettingsBase + "/devices/" + pathSegment(deviceId) + "/settings",
                body: body
            )
        } catch let error as APIError {
            if let conflict: SettingsVersionConflict<S> = Self.conflict(from: error) { throw conflict }
            throw error
        }
    }

    // MARK: - Helpers

    /// The server answers 413 above `MAX_SETTINGS_BYTES`. Checking first turns a
    /// wire failure into a local one at the point the oversized value was chosen.
    private func assertWithinSizeCap<S: Encodable>(_ settings: S) throws {
        let encoded = try JSONEncoder().encode(settings)
        guard encoded.count <= AppSettingsKey.maxSettingsBytes else {
            throw APIError.server(
                "Settings document is \(encoded.count) bytes, over the \(AppSettingsKey.maxSettingsBytes)-byte limit."
            )
        }
    }

    /// "No document yet" is a normal state for these routes, not a failure. The
    /// routes answer 404 **with** a body (`apiError("not_found", …)`), and
    /// `checkResponse` turns any 4xx carrying a body into `.server(message)` — so
    /// matching only `.status(404)` would miss every real response.
    private static func isNotFound(_ error: APIError) -> Bool {
        switch error {
        case .status(404):
            return true
        case .server(let message):
            let normalized = message.lowercased()
            return normalized == "not_found" || normalized == "not found"
        default:
            return false
        }
    }

    /// The 409 body carries `{ extra: { current } }`. `checkResponse` has already
    /// reduced it to a message, so the winning document is re-read from the raw
    /// error text when present and otherwise left nil — the caller re-reads either way.
    private static func conflict<S: Codable>(from error: APIError) -> SettingsVersionConflict<S>? {
        switch error {
        case .status(409):
            return SettingsVersionConflict<S>(current: nil)
        case .server(let message) where message.contains("version_conflict"):
            return SettingsVersionConflict<S>(current: nil)
        default:
            return nil
        }
    }
}
