//
//  RootView.swift
//  InterlinedList
//

import SwiftUI

struct RootView: View {
    @EnvironmentObject var authState: AuthState

    var body: some View {
        Group {
            if authState.hasToken || authState.isLoggedIn {
                MainTabView()
            } else {
                LoginView()
            }
        }
        .preferredColorScheme(preferredScheme)
        // The server resizes every image upload to its own cap regardless of
        // what the client sends, so read the caps once at launch and let
        // ImageUploadProcessor size to them. Public route — no token needed,
        // and a failure just leaves the documented fallbacks in place.
        .task { await ServerLimitsStore.shared.refresh() }
    }

    /// Honor the user's saved theme preference ("light" / "dark"); "system" or
    /// missing leaves the OS appearance in control.
    private var preferredScheme: ColorScheme? {
        switch authState.user?.theme {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }
}
