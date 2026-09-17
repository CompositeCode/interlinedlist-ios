//
//  KeychainService.swift
//  InterlinedList
//

import Foundation
import Security
import os.log

private let keychainLog = Logger(subsystem: "com.interlinedlist.app", category: "KeychainService")

enum KeychainService {
    private static let service = "com.interlinedlist.app"
    private static let tokenAccount = "syncToken"

    static func saveToken(_ token: String) -> Bool {
        guard let data = token.data(using: .utf8) else { return false }
        // Identity attributes used to locate an existing item; delete-then-add
        // avoids errSecDuplicateItem. Never include the token value in the delete
        // query so a stale item with different accessibility is still removed.
        let identity: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: tokenAccount,
        ]
        SecItemDelete(identity as CFDictionary)
        var attributes = identity
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status != errSecSuccess {
            // Log the code (never the token). errSecMissingEntitlement (-34018)
            // here means the running build lacks the keychain-access-group
            // entitlement — i.e. it was ad-hoc signed, not signed with the team.
            let message = (SecCopyErrorMessageString(status, nil) as String?) ?? "unknown error"
            keychainLog.error("saveToken failed: OSStatus \(status) (\(message, privacy: .public))")
        }
        return status == errSecSuccess
    }

    static func loadToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: tokenAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8) else {
            return nil
        }
        return token
    }

    // MARK: - Device identity

    private static let deviceIdAccount = "appSettingsDeviceId"

    /// A stable id for this install, used by the settings-sync service.
    ///
    /// Keychain, not `UserDefaults`: the id must survive for as long as the install
    /// does, and it sits alongside the sync token it is presented with. Generated
    /// once on first read and reused thereafter. Returns nil only if the keychain
    /// itself is unavailable — callers must treat sync as unavailable rather than
    /// minting a fresh id every launch, which would register a new device each time.
    static func deviceId() -> String? {
        if let existing = load(account: deviceIdAccount) { return existing }
        let generated = UUID().uuidString
        guard save(generated, account: deviceIdAccount) else { return nil }
        return generated
    }

    /// Deliberately NOT cleared on logout: the device identity belongs to the
    /// install, not the session, and re-registering on every sign-in would litter
    /// the account's device list.
    static func deleteDeviceId() -> Bool {
        delete(account: deviceIdAccount)
    }

    // MARK: - Shared primitives

    private static func save(_ value: String, account: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        let identity: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(identity as CFDictionary)
        var attributes = identity
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status != errSecSuccess {
            let message = (SecCopyErrorMessageString(status, nil) as String?) ?? "unknown error"
            keychainLog.error("save(\(account, privacy: .public)) failed: OSStatus \(status) (\(message, privacy: .public))")
        }
        return status == errSecSuccess
    }

    private static func load(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return value
    }

    private static func delete(account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    static func deleteToken() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: tokenAccount,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
