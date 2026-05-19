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
    @State private var unreadCount = 0
    @State private var pendingRequestCount = 0
    @State private var showNotifications = false

    var body: some View {
        VStack(spacing: 0) {
            topBar
            sectionContent
        }
        .background(Color(.systemGroupedBackground))
        .task {
            await refreshCounts()
        }
    }

    private var topBar: some View {
        HStack(spacing: 0) {
            ForEach([MainSection.home, .lists, .documents, .profile], id: \.rawValue) { section in
                topBarButton(section: section)
            }
            bellButton
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

    private var bellButton: some View {
        Button {
            showNotifications = true
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "bell")
                    .font(.title3)
                    .foregroundStyle(Color.secondary)
                    .frame(maxWidth: .infinity)
                let total = unreadCount + pendingRequestCount
                if total > 0 {
                    Text(total > 99 ? "99+" : "\(total)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color.red)
                        .clipShape(Capsule())
                        .offset(x: 6, y: -4)
                }
            }
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showNotifications, onDismiss: {
            Task { await refreshCounts() }
        }) {
            NotificationsView()
                .environmentObject(authState)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var profileAvatar: some View {
        ZStack(alignment: .topTrailing) {
            if let avatarURLString = authState.user?.avatar, let url = URL(string: avatarURLString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure, .empty:
                        Image(systemName: "person.circle.fill").resizable().scaledToFit()
                    @unknown default:
                        Image(systemName: "person.circle.fill").resizable().scaledToFit()
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
            if pendingRequestCount > 0 {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 8, height: 8)
                    .offset(x: 2, y: -2)
            }
        }
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch selectedSection {
        case .home:
            FeedView()
        case .lists:
            ListsView()
        case .documents:
            DocumentsView()
        case .profile:
            ProfileView()
        }
    }

    private func refreshCounts() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.fetchNotificationCount() }
            group.addTask { await self.fetchFollowRequestCount() }
        }
    }

    private func fetchNotificationCount() async {
        do {
            let response = try await APIClient.shared.notifications()
            unreadCount = response.unreadCount
        } catch {
            // Silently ignore — badge just shows 0
        }
    }

    private func fetchFollowRequestCount() async {
        do {
            let requests = try await APIClient.shared.followRequests()
            pendingRequestCount = requests.count
        } catch {
            // Silently ignore
        }
    }
}

// MARK: - Profile

private struct ProfileView: View {
    @EnvironmentObject var authState: AuthState
    @State private var showEditProfile = false

    var body: some View {
        NavigationStack {
            List {
                if let user = authState.user {
                    identitySection(user: user)
                    accountSection(user: user)
                    preferencesSection(user: user)
                }
                Section("Social") {
                    NavigationLink(destination: FollowRequestsView().environmentObject(authState)) {
                        Label("Follow Requests", systemImage: "person.crop.circle.badge.plus")
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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit") {
                        showEditProfile = true
                    }
                }
            }
            .sheet(isPresented: $showEditProfile) {
                if let user = authState.user {
                    EditProfileView(user: user)
                        .environmentObject(authState)
                }
            }
        }
    }

    @ViewBuilder
    private func identitySection(user: User) -> some View {
        Section {
            HStack(spacing: 14) {
                avatarView(url: user.avatar.flatMap { URL(string: $0) }, size: 64)
                VStack(alignment: .leading, spacing: 3) {
                    Text(user.displayNameOrUsername)
                        .font(.headline)
                    Text("@\(user.username)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 6)
            if let bio = user.bio, !bio.isEmpty {
                Text(bio)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func accountSection(user: User) -> some View {
        Section("Account") {
            LabeledContent("Email") {
                HStack(spacing: 6) {
                    Text(user.email)
                        .foregroundStyle(.primary)
                    if user.emailVerified == true {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                            .imageScale(.small)
                    }
                }
            }
            if let createdAt = user.createdAt, let date = parseDate(createdAt) {
                LabeledContent("Member since", value: date.formatted(.dateTime.month(.wide).year()))
            }
        }
    }

    @ViewBuilder
    private func preferencesSection(user: User) -> some View {
        Section("Preferences") {
            if let theme = user.theme, !theme.isEmpty {
                LabeledContent("Theme", value: theme.capitalized)
            }
            LabeledContent("Default post visibility") {
                Text(user.defaultPubliclyVisible == true ? "Public" : "Private")
                    .foregroundStyle(.secondary)
            }
            if user.showAdvancedPostSettings == true {
                Label("Advanced post settings", systemImage: "checkmark")
                    .foregroundStyle(.secondary)
            }
            if let maxLen = user.maxMessageLength {
                LabeledContent("Max message length", value: maxLen, format: .number)
            }
        }
    }

    @ViewBuilder
    private func avatarView(url: URL?, size: CGFloat) -> some View {
        if let url {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    Image(systemName: "person.circle.fill").resizable().scaledToFit()
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
        } else {
            Image(systemName: "person.circle.fill")
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .foregroundStyle(.secondary)
        }
    }

    private func parseDate(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}
