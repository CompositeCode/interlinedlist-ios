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
    }
}
