//
//  ThemePreference.swift
//  InterlinedList
//

import Foundation
import SwiftUI

/// The account's display-theme choice, as the server stores it ("system" / "light" / "dark").
enum ThemePreference: String, CaseIterable {
    case system
    case light
    case dark

    /// `UserDefaults` key for the mirror of the server value. A display preference,
    /// not a credential, so the Keychain-only rule for tokens does not apply here.
    static let storageKey = "themePreference"

    /// Anything the server (or the mirror) can't be read as a known theme means
    /// "follow the OS" — the same fallback `RootView` applied before.
    init(stored value: String?) {
        self = ThemePreference(rawValue: value?.lowercased() ?? "") ?? .system
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    /// The account value is authoritative once `GET /api/user` has answered; until
    /// then — the login screen, a cold launch, an offline start — the mirror stands in.
    static func resolve(serverTheme: String?, mirrored: String?) -> ThemePreference {
        if let serverTheme {
            return ThemePreference(stored: serverTheme)
        }
        return ThemePreference(stored: mirrored)
    }
}

/// Writes the theme mirror that `RootView` reads at first render.
struct ThemePreferenceStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var current: ThemePreference {
        ThemePreference(stored: defaults.string(forKey: ThemePreference.storageKey))
    }

    func save(_ theme: String?) {
        defaults.set(ThemePreference(stored: theme).rawValue, forKey: ThemePreference.storageKey)
    }
}
