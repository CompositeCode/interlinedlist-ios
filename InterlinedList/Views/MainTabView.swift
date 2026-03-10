//
//  MainTabView.swift
//  InterlinedList
//

import SwiftUI

/// Top-level sections: Home (messages feed), Lists, Documents, Profile.
private enum MainSection: Int, CaseIterable {
    case home
    case lists
    case documents
    case profile
}

struct MainTabView: View {
    @EnvironmentObject var authState: AuthState
    @State private var selectedSection: MainSection = .home

    var body: some View {
        VStack(spacing: 0) {
            topBar
            sectionContent
        }
        .background(Color(.systemGroupedBackground))
    }

    private var topBar: some View {
        HStack(spacing: 0) {
            ForEach([MainSection.home, .lists, .documents, .profile], id: \.rawValue) { section in
                topBarButton(section: section)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemGroupedBackground))
    }

    @ViewBuilder
    private func topBarButton(section: MainSection) -> some View {
        Button {
            selectedSection = section
        } label: {
            Group {
                switch section {
                case .home:
                    Image(systemName: "house")
                case .lists:
                    Image(systemName: "list.bullet.rectangle")
                case .documents:
                    Image(systemName: "doc.text")
                case .profile:
                    profileAvatar
                }
            }
            .font(.title3)
            .foregroundStyle(selectedSection == section ? Color.accentColor : Color.secondary)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var profileAvatar: some View {
        if let avatarURLString = authState.user?.avatar, let url = URL(string: avatarURLString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure, .empty:
                    Image(systemName: "person.circle.fill")
                        .resizable()
                        .scaledToFit()
                @unknown default:
                    Image(systemName: "person.circle.fill")
                        .resizable()
                        .scaledToFit()
                }
            }
            .frame(width: 28, height: 28)
            .clipShape(Circle())
        } else {
            Image(systemName: "person.circle.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 28, height: 28)
        }
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch selectedSection {
        case .home:
            FeedView()
        case .lists:
            ListsPlaceholderView()
        case .documents:
            DocumentsPlaceholderView()
        case .profile:
            ProfileView()
        }
    }
}

// MARK: - Placeholder & profile

private struct ListsPlaceholderView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label("Lists", systemImage: "list.bullet.rectangle")
            } description: {
                Text("Lists are not yet available in this app.")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Lists")
        }
    }
}

private struct DocumentsPlaceholderView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label("Documents", systemImage: "doc.text")
            } description: {
                Text("Documents are not yet available in this app.")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Documents")
        }
    }
}

private struct ProfileView: View {
    @EnvironmentObject var authState: AuthState

    var body: some View {
        NavigationStack {
        List {
            if let user = authState.user {
                Section {
                    HStack(spacing: 12) {
                        if let avatarURLString = user.avatar, let url = URL(string: avatarURLString) {
                            AsyncImage(url: url) { phase in
                                if let image = phase.image {
                                    image.resizable().scaledToFill()
                                } else {
                                    Image(systemName: "person.circle.fill")
                                        .resizable()
                                        .scaledToFit()
                                }
                            }
                            .frame(width: 60, height: 60)
                            .clipShape(Circle())
                        } else {
                            Image(systemName: "person.circle.fill")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 60, height: 60)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(user.displayNameOrUsername)
                                .font(.headline)
                            Text("@\(user.username)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            Section {
                Button(role: .destructive) {
                    authState.logout()
                } label: {
                    Label("Log out", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
        }
        .navigationTitle("Profile")
        }
    }
}
