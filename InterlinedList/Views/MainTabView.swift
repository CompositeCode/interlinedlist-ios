//
//  MainTabView.swift
//  InterlinedList
//

import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var authState: AuthState

    var body: some View {
        TabView {
            FeedView()
                .tabItem {
                    Label("Feed", systemImage: "list.bullet")
                }
            ComposeView()
                .tabItem {
                    Label("Post", systemImage: "square.and.pencil")
                }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if let user = authState.user {
                        Text(user.displayNameOrUsername)
                            .font(.caption)
                    }
                    Button(role: .destructive) {
                        authState.logout()
                    } label: {
                        Label("Log out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                } label: {
                    Image(systemName: "person.circle.fill")
                }
            }
        }
    }
}
