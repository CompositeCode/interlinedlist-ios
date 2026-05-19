//
//  UserProfileView.swift
//  InterlinedList
//

import SwiftUI

struct UserProfileView: View {
    let username: String

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var authState: AuthState
    @State private var selectedTab = 0
    @State private var messages: [Message] = []
    @State private var lists: [UserList] = []
    @State private var isLoadingMessages = true
    @State private var isLoadingLists = false
    @State private var messagesError: String?
    @State private var listsError: String?
    @State private var pagination: Pagination?
    @State private var targetUserId: String?
    @State private var followStatus: FollowStatus?
    @State private var followCounts: FollowCounts?
    @State private var isFollowLoading = false
    @State private var followError: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if authState.user?.username != username {
                    followHeader
                }

                Picker("Content", selection: $selectedTab) {
                    Text("Posts").tag(0)
                    Text("Lists").tag(1)
                }
                .pickerStyle(.segmented)
                .padding()

                if selectedTab == 0 {
                    messagesTab
                } else {
                    listsTab
                }
            }
            .navigationTitle("@\(username)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                await loadMessages()
            }
            .onChange(of: selectedTab) { _, tab in
                if tab == 1 && lists.isEmpty && listsError == nil {
                    Task { await loadLists() }
                }
            }
        }
    }

    @ViewBuilder
    private var followHeader: some View {
        VStack(spacing: 8) {
            HStack(spacing: 24) {
                if let counts = followCounts {
                    VStack(spacing: 2) {
                        Text("\(counts.followers)")
                            .font(.headline)
                        Text("Followers")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    VStack(spacing: 2) {
                        Text("\(counts.following)")
                            .font(.headline)
                        Text("Following")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if targetUserId != nil {
                    followButton
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)

            if let error = followError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
            }
        }
        Divider()
    }

    @ViewBuilder
    private var followButton: some View {
        if isFollowLoading {
            ProgressView()
                .frame(width: 80, height: 32)
        } else if followStatus?.pendingRequest == true {
            Button("Requested") { Task { await toggleFollow() } }
                .buttonStyle(.bordered)
                .controlSize(.small)
        } else if followStatus?.following == true {
            Button("Following") { Task { await toggleFollow() } }
                .buttonStyle(.bordered)
                .controlSize(.small)
        } else {
            Button("Follow") { Task { await toggleFollow() } }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
    }

    @ViewBuilder
    private var messagesTab: some View {
        if isLoadingMessages && messages.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = messagesError, messages.isEmpty {
            ContentUnavailableView {
                Label("Unable to load", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            } actions: {
                Button("Retry") { Task { await loadMessages() } }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if messages.isEmpty {
            ContentUnavailableView {
                Label("No Posts", systemImage: "text.bubble")
            } description: {
                Text("@\(username) has no public posts.")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(messages) { message in
                    PublicMessageRow(message: message)
                }
                if let pag = pagination, pag.hasMore, !isLoadingMessages {
                    HStack { Spacer(); ProgressView(); Spacer() }
                        .onAppear { Task { await loadMoreMessages() } }
                }
            }
            .refreshable { await loadMessages() }
        }
    }

    @ViewBuilder
    private var listsTab: some View {
        if isLoadingLists {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = listsError {
            ContentUnavailableView {
                Label("Unable to load", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            } actions: {
                Button("Retry") { Task { await loadLists() } }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if lists.isEmpty {
            ContentUnavailableView {
                Label("No Lists", systemImage: "list.bullet.rectangle")
            } description: {
                Text("@\(username) has no public lists.")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(lists) { list in
                VStack(alignment: .leading, spacing: 4) {
                    Text(list.name)
                        .font(.body)
                    if let desc = list.description, !desc.isEmpty {
                        Text(desc)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let count = list.itemCount {
                        Text("\(count) items")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }
            .refreshable { await loadLists() }
        }
    }

    private func loadMessages() async {
        messagesError = nil
        isLoadingMessages = true
        defer { isLoadingMessages = false }
        do {
            let (msgs, pag) = try await APIClient.shared.publicMessages(username: username)
            messages = msgs
            pagination = pag
            if targetUserId == nil {
                targetUserId = messages.first?.userId
                if let userId = targetUserId, userId != authState.user?.id {
                    Task { await loadFollowInfo(userId: userId) }
                }
            }
        } catch {
            messagesError = "Could not load posts."
        }
    }

    private func loadMoreMessages() async {
        guard let pag = pagination, pag.hasMore else { return }
        isLoadingMessages = true
        defer { isLoadingMessages = false }
        do {
            let (more, pag) = try await APIClient.shared.publicMessages(username: username, limit: 50, offset: messages.count)
            messages.append(contentsOf: more)
            pagination = pag
        } catch {}
    }

    private func loadLists() async {
        listsError = nil
        isLoadingLists = true
        defer { isLoadingLists = false }
        do {
            lists = try await APIClient.shared.publicLists(username: username)
        } catch {
            listsError = "Could not load lists."
        }
    }

    private func loadFollowInfo(userId: String) async {
        do {
            async let statusTask = APIClient.shared.followStatus(userId: userId)
            async let countsTask = APIClient.shared.followCounts(userId: userId)
            let (status, counts) = try await (statusTask, countsTask)
            followStatus = status
            followCounts = counts
        } catch {
            // Follow info is supplementary — silently ignore errors
        }
    }

    private func toggleFollow() async {
        guard let userId = targetUserId else { return }
        isFollowLoading = true
        defer { isFollowLoading = false }
        followError = nil
        do {
            if followStatus?.following == true {
                try await APIClient.shared.unfollowUser(userId: userId)
                followStatus = FollowStatus(following: false, followedBy: followStatus?.followedBy ?? false, pendingRequest: false)
                followCounts = followCounts.map { FollowCounts(followers: max(0, $0.followers - 1), following: $0.following) }
            } else {
                let updated = try await APIClient.shared.followUser(userId: userId)
                followStatus = updated
                if updated.following {
                    followCounts = followCounts.map { FollowCounts(followers: $0.followers + 1, following: $0.following) }
                }
            }
        } catch APIError.status(401) {
            authState.handleUnauthorized()
        } catch APIError.server(let msg) {
            followError = msg
        } catch {
            followError = "Action failed. Please try again."
        }
    }
}

private struct PublicMessageRow: View {
    let message: Message

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(message.authorDisplay)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Text(formatDate(message.createdAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(message.content)
                .font(.body)
            if let tags = message.tags, !tags.isEmpty {
                HStack(spacing: 6) {
                    ForEach(tags, id: \.self) { tag in
                        Text(tag)
                            .font(.caption2)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color(.secondarySystemFill))
                            .clipShape(Capsule())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func formatDate(_ iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) {
            let f = RelativeDateTimeFormatter()
            f.unitsStyle = .abbreviated
            return f.localizedString(for: date, relativeTo: Date())
        }
        return iso
    }
}

#Preview {
    UserProfileView(username: "testuser")
        .environmentObject(AuthState())
}
