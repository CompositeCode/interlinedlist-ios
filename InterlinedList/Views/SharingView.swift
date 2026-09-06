//
//  SharingView.swift
//  InterlinedList
//

import SwiftUI
import UIKit

/// A normalized per-person access grant, unified from either a `DocumentCollaborator`
/// (documents) or a `ListWatcher` (lists) so one screen renders both.
struct AccessMember: Identifiable {
    let userId: String
    let displayName: String
    let username: String?
    let avatar: String?
    let role: WatcherRole
    var id: String { userId }
}

/// Owner-facing, single-screen sharing for a list or document — parity with the web
/// "Access & Permissions" page: invite people (with an email-or-silent toggle), a
/// members list (role / Get link / Remove), email invites, tokenized share links, and
/// a Make-public toggle. Create actions are subscriber-gated (hidden for free users);
/// listing and revoking are always available to the owner.
struct SharingView: View {
    let kind: ShareResourceKind
    let resourceId: String
    let title: String
    /// Persists the public flag from the parent (which holds the full model), so this
    /// screen doesn't need the resource's title/content. Throws so the toggle reverts.
    let setPublic: (Bool) async throws -> Void

    @EnvironmentObject private var authState: AuthState
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: SharingModel

    @State private var newRole: WatcherRole = .watcher
    @State private var emailThisPerson = true
    @State private var searchText = ""

    @State private var inviteEmail = ""
    @State private var inviteRole: WatcherRole = .watcher
    @State private var inviteExpiry: ShareExpiryPreset = .never

    @State private var linkRole: WatcherRole = .watcher
    @State private var linkExpiry: ShareExpiryPreset = .never

    @State private var isPublic: Bool
    @State private var copiedId: String?

    init(kind: ShareResourceKind, resourceId: String, title: String, isPublic: Bool,
         setPublic: @escaping (Bool) async throws -> Void) {
        self.kind = kind
        self.resourceId = resourceId
        self.title = title
        self.setPublic = setPublic
        _isPublic = State(initialValue: isPublic)
        _model = StateObject(wrappedValue: SharingModel(kind: kind, resourceId: resourceId))
    }

    private var noun: String { kind.singularLabel }
    private var canManage: Bool { authState.user?.isSubscriber == true }

    var body: some View {
        NavigationStack {
            Form {
                accessSection
                inviteSection
                linksSection
                publicSection
            }
            .navigationTitle("Share")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                model.handleUnauthorized = { authState.handleUnauthorized() }
                await model.loadAll()
            }
            .onChange(of: searchText) { _, query in
                model.scheduleSearch(query)
            }
        }
    }

    // MARK: Access & permissions (per-person)

    @ViewBuilder
    private var accessSection: some View {
        Section {
            if canManage {
                Picker("Role for new users", selection: $newRole) {
                    ForEach(WatcherRole.allCases, id: \.self) { role in
                        Text(role.accessLabel).tag(role)
                    }
                }
                Text(newRole.accessDetail(for: noun))
                    .font(.ilBody(13)).foregroundStyle(.secondary)

                Toggle("Email this person", isOn: $emailThisPerson)

                TextField("Search by name, username, or email", text: $searchText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                ForEach(model.candidates) { candidate in
                    Button {
                        Task { await addCandidate(candidate) }
                    } label: {
                        HStack {
                            memberLabel(name: candidate.displayNameOrUsername, username: candidate.username, avatar: candidate.avatar)
                            Spacer()
                            Text("Add as \(newRole.accessLabel)")
                                .font(.ilBody(13)).foregroundStyle(ILColor.link)
                        }
                    }
                }
            }

            if model.members.isEmpty {
                Text("No one else has access yet.")
                    .foregroundStyle(.secondary).font(.ilBody(14))
            } else {
                ForEach(model.members) { member in
                    memberRow(member)
                }
            }
        } header: {
            Text("Access & Permissions")
        } footer: {
            if canManage {
                Text("Uncheck “Email this person” to share silently (in-app notification only).")
            } else {
                Text("Subscribe to invite people to this \(noun).")
            }
        }
    }

    private func memberRow(_ member: AccessMember) -> some View {
        HStack(spacing: 10) {
            memberLabel(name: member.displayName, username: member.username, avatar: member.avatar)
            Spacer()
            if canManage {
                Menu {
                    ForEach(WatcherRole.allCases, id: \.self) { role in
                        Button(role.accessLabel) { Task { await setRole(member, role) } }
                    }
                } label: {
                    Text(member.role.accessLabel).font(.ilBody(13)).foregroundStyle(ILColor.link)
                }
            } else {
                Text(member.role.accessLabel).font(.ilBody(13)).foregroundStyle(.secondary)
            }
            copyButton(id: "member-\(member.userId)") {
                ILWebURL.resource(kind: kind, id: resourceId)?.absoluteString
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                Task { await removeMember(member) }
            } label: {
                Label("Remove", systemImage: "person.badge.minus")
            }
        }
    }

    // MARK: Invite by email

    @ViewBuilder
    private var inviteSection: some View {
        Section {
            if canManage {
                TextField("name@example.com", text: $inviteEmail)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Picker("Role", selection: $inviteRole) {
                    ForEach(WatcherRole.allCases, id: \.self) { Text($0.accessLabel).tag($0) }
                }
                Picker("Expires", selection: $inviteExpiry) {
                    ForEach(ShareExpiryPreset.allCases) { Text($0.label).tag($0) }
                }
                Button("Send invite") { Task { await sendInvite() } }
                    .disabled(!isEmailValid(inviteEmail) || model.isSending)
            }

            if !model.invites.isEmpty {
                ForEach(model.invites) { invite in
                    inviteRow(invite)
                }
            }
        } header: {
            Text("Invite by email")
        } footer: {
            if model.invites.isEmpty && !canManage {
                Text("Invite people who don’t have an account yet — they get access when they accept.")
            }
        }
    }

    private func inviteRow(_ invite: ShareInvite) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(invite.email)
            HStack(spacing: 8) {
                Text((invite.shareRole ?? .watcher).accessLabel)
                Text("·")
                Text((invite.accepted == true) ? "Accepted" : "Pending")
                    .foregroundStyle((invite.accepted == true) ? Color.green : Color.secondary)
                Text("·")
                Text(expiryText(invite.expiresAt))
            }
            .font(.ilBody(12)).foregroundStyle(.secondary)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                Task { await revokeInvite(invite) }
            } label: {
                Label("Revoke", systemImage: "trash")
            }
        }
    }

    // MARK: Share links

    @ViewBuilder
    private var linksSection: some View {
        Section {
            if canManage {
                Picker("Role", selection: $linkRole) {
                    ForEach(WatcherRole.allCases, id: \.self) { Text($0.linkLabel).tag($0) }
                }
                Text(linkRole.linkDetail).font(.ilBody(13)).foregroundStyle(.secondary)
                Picker("Expires", selection: $linkExpiry) {
                    ForEach(ShareExpiryPreset.allCases) { Text($0.label).tag($0) }
                }
                Button("Create link") { Task { await createLink() } }
                    .disabled(model.isSending)
            }

            if model.links.isEmpty {
                Text("No share links yet.").foregroundStyle(.secondary).font(.ilBody(14))
            } else {
                ForEach(model.links) { link in
                    linkRow(link)
                }
            }
        } header: {
            Text("Share links")
        }
    }

    private func linkRow(_ link: ShareLink) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text((link.shareRole ?? .watcher).linkLabel)
                Text(expiryText(link.expiresAt)).font(.ilBody(12)).foregroundStyle(.secondary)
            }
            Spacer()
            copyButton(id: "link-\(link.token)") { link.url }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                Task { await revokeLink(link) }
            } label: {
                Label("Revoke", systemImage: "trash")
            }
        }
    }

    // MARK: Make public

    @ViewBuilder
    private var publicSection: some View {
        Section {
            Toggle("Public", isOn: Binding(
                get: { isPublic },
                set: { newValue in Task { await togglePublic(newValue) } }
            ))
            if isPublic, let url = publicURL {
                copyButton(id: "public", label: "Copy public link") { url.absoluteString }
            }
        } header: {
            Text("Make public")
        } footer: {
            Text(isPublic
                 ? "Anyone with the link can view — no account needed. Shown on your profile."
                 : "Off: only people you invite can access this \(noun). Turn on to let anyone with the link view it.")
        }
    }

    private var publicURL: URL? {
        guard let username = authState.user?.username, !username.isEmpty else {
            return ILWebURL.resource(kind: kind, id: resourceId)
        }
        return ILWebURL.publicResource(kind: kind, ownerUsername: username, id: resourceId)
    }

    // MARK: Shared subviews / helpers

    @ViewBuilder
    private func memberLabel(name: String, username: String?, avatar: String?) -> some View {
        HStack(spacing: 8) {
            avatarView(avatar)
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                if let username, !username.isEmpty {
                    Text("@\(username)").font(.ilBody(12)).foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func avatarView(_ avatar: String?) -> some View {
        if let avatar, avatar.hasPrefix("http"), let url = URL(string: avatar) {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Image(systemName: "person.crop.circle.fill").foregroundStyle(.secondary)
            }
            .frame(width: 28, height: 28)
            .clipShape(Circle())
        } else {
            Image(systemName: "person.crop.circle.fill")
                .resizable().frame(width: 28, height: 28).foregroundStyle(.secondary)
        }
    }

    private func copyButton(id: String, label: String = "Get link", value: @escaping () -> String?) -> some View {
        Button {
            if let value = value() {
                UIPasteboard.general.string = value
                copiedId = id
                Task {
                    try? await Task.sleep(nanoseconds: 1_800_000_000)
                    if copiedId == id { copiedId = nil }
                }
            }
        } label: {
            Text(copiedId == id ? "Copied!" : label)
                .font(.ilBody(13)).foregroundStyle(ILColor.link)
        }
        .buttonStyle(.borderless)
    }

    private func expiryText(_ iso: String?) -> String {
        guard let iso, !iso.isEmpty else { return "No expiry" }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = f.date(from: iso)
        if date == nil { f.formatOptions = [.withInternetDateTime]; date = f.date(from: iso) }
        guard let date else { return "Expires \(iso)" }
        return "Expires " + DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .none)
    }

    private func isEmailValid(_ email: String) -> Bool {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.contains("@") && trimmed.contains(".") && !trimmed.hasSuffix("@")
    }

    // MARK: Actions

    private func addCandidate(_ candidate: WatcherCandidate) async {
        await model.addMember(userId: candidate.id, role: newRole, notify: emailThisPerson)
        searchText = ""
    }

    private func setRole(_ member: AccessMember, _ role: WatcherRole) async {
        await model.setRole(userId: member.userId, role: role)
    }

    private func removeMember(_ member: AccessMember) async {
        await model.removeMember(userId: member.userId)
    }

    private func sendInvite() async {
        let email = inviteEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isEmailValid(email) else { return }
        await model.sendInvite(email: email, role: inviteRole, expiresAt: inviteExpiry.expiresAt())
        inviteEmail = ""
    }

    private func revokeInvite(_ invite: ShareInvite) async {
        await model.revokeInvite(token: invite.token)
    }

    private func createLink() async {
        if let created = await model.createLink(role: linkRole, expiresAt: linkExpiry.expiresAt()) {
            UIPasteboard.general.string = created.url
            copiedId = "link-\(created.token)"
        }
    }

    private func revokeLink(_ link: ShareLink) async {
        await model.revokeLink(token: link.token)
    }

    private func togglePublic(_ newValue: Bool) async {
        let previous = isPublic
        isPublic = newValue
        do {
            try await setPublic(newValue)
        } catch {
            isPublic = previous
        }
    }
}

/// Holds all sharing state for one resource and performs the async operations,
/// branching on `kind` only for the per-person section (documents use
/// collaborators, lists use watchers; links & invites are already kind-generic).
@MainActor
final class SharingModel: ObservableObject {
    let kind: ShareResourceKind
    let resourceId: String

    @Published var members: [AccessMember] = []
    @Published var invites: [ShareInvite] = []
    @Published var links: [ShareLink] = []
    @Published var candidates: [WatcherCandidate] = []
    @Published var isSending = false

    var handleUnauthorized: (() -> Void)?
    private var searchTask: Task<Void, Never>?

    init(kind: ShareResourceKind, resourceId: String) {
        self.kind = kind
        self.resourceId = resourceId
    }

    func loadAll() async {
        async let membersTask = fetchMembers()
        async let invitesTask = try? APIClient.shared.shareInvites(kind: kind, id: resourceId)
        async let linksTask = try? APIClient.shared.shareLinks(kind: kind, id: resourceId)
        members = await membersTask
        invites = await invitesTask ?? []
        links = await linksTask ?? []
    }

    private func fetchMembers() async -> [AccessMember] {
        do {
            switch kind {
            case .documents:
                return try await APIClient.shared.documentCollaborators(id: resourceId).map {
                    AccessMember(userId: $0.userId, displayName: $0.displayNameOrUsername,
                                 username: $0.username, avatar: $0.avatar, role: $0.collaboratorRole ?? .watcher)
                }
            case .lists:
                return try await APIClient.shared.listWatchers(listId: resourceId).map {
                    AccessMember(userId: $0.userId, displayName: $0.user?.displayNameOrUsername ?? "User",
                                 username: $0.user?.username, avatar: $0.user?.avatar, role: $0.watcherRole ?? .watcher)
                }
            }
        } catch APIError.status(401) {
            handleUnauthorized?()
            return []
        } catch {
            return []
        }
    }

    func scheduleSearch(_ query: String) {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { candidates = []; return }
        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard let self, !Task.isCancelled else { return }
            let results = await self.runSearch(trimmed)
            if !Task.isCancelled { self.candidates = results }
        }
    }

    private func runSearch(_ query: String) async -> [WatcherCandidate] {
        do {
            switch kind {
            case .documents:
                return try await APIClient.shared.searchDocumentCollaboratorCandidates(id: resourceId, query: query)
            case .lists:
                return try await APIClient.shared.searchWatcherCandidates(listId: resourceId, search: query)
            }
        } catch {
            return []
        }
    }

    func addMember(userId: String, role: WatcherRole, notify: Bool) async {
        await perform {
            switch self.kind {
            case .documents:
                _ = try await APIClient.shared.addDocumentCollaborator(id: self.resourceId, userId: userId, role: role, notify: notify)
            case .lists:
                _ = try await APIClient.shared.addWatcher(listId: self.resourceId, userId: userId, role: role, notify: notify)
            }
        }
        candidates = []
        members = await fetchMembers()
    }

    func setRole(userId: String, role: WatcherRole) async {
        await perform {
            switch self.kind {
            case .documents:
                _ = try await APIClient.shared.setDocumentCollaboratorRole(id: self.resourceId, userId: userId, role: role)
            case .lists:
                _ = try await APIClient.shared.setWatcherRole(listId: self.resourceId, userId: userId, role: role)
            }
        }
        members = await fetchMembers()
    }

    func removeMember(userId: String) async {
        await perform {
            switch self.kind {
            case .documents:
                try await APIClient.shared.removeDocumentCollaborator(id: self.resourceId, userId: userId)
            case .lists:
                try await APIClient.shared.removeWatcher(listId: self.resourceId, userId: userId)
            }
        }
        members.removeAll { $0.userId == userId }
    }

    func sendInvite(email: String, role: WatcherRole, expiresAt: String?) async {
        isSending = true
        await perform {
            _ = try await APIClient.shared.createShareInvite(kind: self.kind, id: self.resourceId, email: email, role: role, expiresAt: expiresAt)
        }
        isSending = false
        invites = (try? await APIClient.shared.shareInvites(kind: kind, id: resourceId)) ?? invites
    }

    func revokeInvite(token: String) async {
        await perform { try await APIClient.shared.revokeShareInvite(kind: self.kind, id: self.resourceId, token: token) }
        invites.removeAll { $0.token == token }
    }

    func createLink(role: WatcherRole, expiresAt: String?) async -> ShareLink? {
        isSending = true
        defer { isSending = false }
        do {
            let link = try await APIClient.shared.createShareLink(kind: kind, id: resourceId, role: role, expiresAt: expiresAt)
            links.insert(link, at: 0)
            return link
        } catch APIError.status(401) {
            handleUnauthorized?()
            return nil
        } catch {
            return nil
        }
    }

    func revokeLink(token: String) async {
        await perform { try await APIClient.shared.revokeShareLink(kind: self.kind, id: self.resourceId, token: token) }
        links.removeAll { $0.token == token }
    }

    private func perform(_ op: @escaping () async throws -> Void) async {
        do {
            try await op()
        } catch APIError.status(401) {
            handleUnauthorized?()
        } catch {
        }
    }
}

#Preview {
    SharingView(kind: .documents, resourceId: "d1", title: "My Doc", isPublic: false) { _ in }
        .environmentObject(AuthState())
}
