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
