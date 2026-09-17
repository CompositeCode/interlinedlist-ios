//
//  RootView.swift
//  InterlinedList
//

import SwiftUI

struct RootView: View {
    @EnvironmentObject var authState: AuthState
    /// Read synchronously at first render, so the saved theme is in force before
    /// `GET /api/user` answers — no flash of the OS appearance, and it survives
    /// an offline cold start.
    @AppStorage(ThemePreference.storageKey) private var mirroredTheme = ThemePreference.system.rawValue

    var body: some View {
        Group {
            if authState.hasToken || authState.isLoggedIn {
                MainTabView()
            } else {
                LoginView()
            }
        }
        .preferredColorScheme(preferredScheme)
        .tint(ILColor.link)
        // The server resizes every image upload to its own cap regardless of
        // what the client sends, so read the caps once at launch and let
        // ImageUploadProcessor size to them. Public route — no token needed,
        // and a failure just leaves the documented fallbacks in place.
        .task { await ServerLimitsStore.shared.refresh() }
    }

    private var preferredScheme: ColorScheme? {
        ThemePreference.resolve(serverTheme: authState.user?.theme, mirrored: mirroredTheme).colorScheme
    }
}
