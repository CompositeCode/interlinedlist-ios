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
    @EnvironmentObject var store: AppDataStore
    @State private var selectedSection: MainSection = .home
    @State private var showNotifications = false

    var body: some View {
        VStack(spacing: 0) {
            topBar
            EmailVerificationBanner()
                .environmentObject(authState)
            sectionContent
        }
        .background(ILColor.background)
        .task {
            await store.prefetchAll(userId: authState.user?.id)
        }
        .onChange(of: authState.user?.id) { _, id in
            if let id { store.onUserIdAvailable(id) }
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
        .background(ILColor.surface)
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
            .font(.ilTitle(20))
            .foregroundStyle(selectedSection == section ? ILColor.primary : Color.secondary)
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
                    .font(.ilTitle(20))
                    .foregroundStyle(Color.secondary)
                    .frame(maxWidth: .infinity)
                let total = store.unreadCount + store.pendingRequestCount
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
            Task { await store.refreshCounts() }
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
            if store.pendingRequestCount > 0 {
                Circle()
                    .fill(ILColor.amber)
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

}

// MARK: - Profile

private struct ProfileView: View {
    @EnvironmentObject var authState: AuthState
    @State private var showEditProfile = false
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            List {
                if let user = authState.user {
                    identitySection(user: user)
                    accountSection(user: user)
                    preferencesSection(user: user)
                }
                Section("Social") {
                    if let userId = authState.user?.id {
                        NavigationLink(destination: FollowListView(userId: userId, mode: .followers, isOwnProfile: true).environmentObject(authState)) {
                            Label("Followers", systemImage: "person.2")
                        }
                        NavigationLink(destination: FollowListView(userId: userId, mode: .following, isOwnProfile: true).environmentObject(authState)) {
                            Label("Following", systemImage: "person.2.fill")
                        }
                    }
                    NavigationLink(destination: FollowRequestsView().environmentObject(authState)) {
                        Label("Follow Requests", systemImage: "person.crop.circle.badge.plus")
                    }
                    NavigationLink(destination: OrganizationsListView().environmentObject(authState)) {
                        Label("Organizations", systemImage: "building.2")
                    }
                    if authState.user?.isSubscriber == true {
                        NavigationLink(destination: LinkedIdentitiesView().environmentObject(authState)) {
                            Label("Linked accounts", systemImage: "link")
                        }
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
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
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
            .sheet(isPresented: $showSettings) {
                SettingsView()
                    .environmentObject(authState)
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
                        .font(.ilTitle())
                    Text("@\(user.username)")
                        .font(.ilBody(15))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 6)
            if let bio = user.bio, !bio.isEmpty {
                Text(bio)
                    .font(.ilBody(15))
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
                            .foregroundStyle(ILColor.primary)
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
