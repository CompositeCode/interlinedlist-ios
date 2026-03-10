//
//  RootView.swift
//  InterlinedList
//

import SwiftUI

struct RootView: View {
    @EnvironmentObject var authState: AuthState

    var body: some View {
        Group {
            if authState.isRestoring {
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .frame(minWidth: 44, minHeight: 44)
            } else if authState.isLoggedIn {
                MainTabView()
            } else {
                LoginView()
            }
        }
    }
}
