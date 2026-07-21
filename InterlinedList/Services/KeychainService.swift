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
