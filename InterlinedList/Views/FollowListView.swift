//
//  FollowListView.swift
//  InterlinedList
//

import SwiftUI

/// A paginated list of a user's followers or accounts they follow.
/// On the current user's own followers list, each row can be removed.
struct FollowListView: View {
    enum Mode {
        case followers
        case following

        var title: String {
            switch self {
            case .followers: return "Followers"
            case .following: return "Following"
            }
        }
    }

    let userId: String
    let mode: Mode
    /// When true and mode is `.followers`, rows expose a "Remove" action.
    var isOwnProfile: Bool = false

    @EnvironmentObject private var authState: AuthState
    @State private var users: [FollowUser] = []
    @State private var pagination: Pagination?
    @State private var isLoading = false
    @State private var error: String?
    @State private var profileTarget: ProfileTarget?

    private let pageSize = 30

    var body: some View {
        Group {
            if isLoading && users.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error, users.isEmpty {
                ContentUnavailableView {
                    Label("Unable to load", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Retry") { Task { await load(reset: true) } }
                }
            } else if users.isEmpty {
                ContentUnavailableView {
                    Label(emptyTitle, systemImage: "person.2")
                } description: {
                    Text(emptyMessage)
                }
            } else {
                List {
                    ForEach(users) { user in
                        Button {
                            profileTarget = ProfileTarget(username: user.username)
                        } label: {
                            FollowUserRow(user: user)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            if canRemove {
                                Button(role: .destructive) {
                                    Task { await remove(user) }
                                } label: {
                                    Label("Remove", systemImage: "person.fill.xmark")
                                }
                            }
                        }
                    }
                    if let pag = pagination, pag.hasMore, !isLoading {
                        HStack { Spacer(); ProgressView(); Spacer() }
                            .onAppear { Task { await load(reset: false) } }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(mode.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if users.isEmpty { await load(reset: true) }
        }
        .sheet(item: $profileTarget) { target in
            UserProfileView(username: target.username)
                .environmentObject(authState)
        }
    }

    private var canRemove: Bool { isOwnProfile && mode == .followers }

    private var emptyTitle: String {
        mode == .followers ? "No followers yet" : "Not following anyone"
    }

    private var emptyMessage: String {
        mode == .followers
            ? "When people follow this account, they'll appear here."
            : "Accounts this user follows will appear here."
    }

    private func load(reset: Bool) async {
        if reset { pagination = nil }
        guard !isLoading else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        let offset = reset ? 0 : users.count
        do {
            let result: (users: [FollowUser], pagination: Pagination?)
            switch mode {
            case .followers:
                result = try await APIClient.shared.followers(userId: userId, limit: pageSize, offset: offset)
            case .following:
                result = try await APIClient.shared.following(userId: userId, limit: pageSize, offset: offset)
            }
            if reset {
                users = result.users
            } else {
                users.append(contentsOf: result.users)
            }
            pagination = result.pagination
        } catch APIError.status(401) {
            authState.handleUnauthorized()
        } catch {
            self.error = "Could not load \(mode.title.lowercased())."
        }
    }

    private func remove(_ user: FollowUser) async {
        do {
            try await APIClient.shared.removeFollower(userId: user.id)
            users.removeAll { $0.id == user.id }
        } catch APIError.status(401) {
            authState.handleUnauthorized()
        } catch {
            self.error = "Could not remove follower."
        }
    }
}

private struct FollowUserRow: View {
    let user: FollowUser

    var body: some View {
        HStack(spacing: 12) {
            avatar
            VStack(alignment: .leading, spacing: 2) {
                Text(user.displayNameOrUsername)
                    .font(.body)
                    .foregroundStyle(.primary)
                Text("@\(user.username)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if user.status == "pending" {
                Text("Pending")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(user.displayNameOrUsername)
    }

    @ViewBuilder
    private var avatar: some View {
        if let avatarURL = user.avatar.flatMap({ URL(string: $0) }) {
            AsyncImage(url: avatarURL) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    Image(systemName: "person.circle.fill").resizable().scaledToFit()
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 40, height: 40)
            .clipShape(Circle())
        } else {
            Image(systemName: "person.circle.fill")
                .resizable().scaledToFit()
                .frame(width: 40, height: 40)
                .foregroundStyle(.secondary)
        }
    }
}

/// Identifiable wrapper so a tapped username can drive a profile sheet.
struct ProfileTarget: Identifiable {
    let id = UUID()
    let username: String
}

#Preview {
    NavigationStack {
        FollowListView(userId: "u1", mode: .followers, isOwnProfile: true)
            .environmentObject(AuthState())
    }
}
