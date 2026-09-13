//
//  OrganizationsView.swift
//  InterlinedList
//

import SwiftUI

/// The organizations the current user belongs to, plus a directory of public
/// organizations they can join.
struct OrganizationsListView: View {
    private enum Scope: String, CaseIterable, Identifiable {
        case mine, discover
        var id: String { rawValue }
        var label: String { self == .mine ? "Mine" : "Discover" }
    }

    @EnvironmentObject private var authState: AuthState
    @State private var scope: Scope = .mine
    @State private var organizations: [Organization] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var showCreate = false

    @State private var directory: [Organization] = []
    @State private var directoryPagination: Pagination?
    @State private var isLoadingDirectory = false
    @State private var directoryError: String?
    @State private var joiningId: String?
    @State private var joinError: String?

    private let pageSize = 20

    var body: some View {
        VStack(spacing: 0) {
            Picker("Scope", selection: $scope) {
                ForEach(Scope.allCases) { option in Text(option.label).tag(option) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.bottom, 8)
            .accessibilityLabel("Organizations to show")

            switch scope {
            case .mine: mineContent
            case .discover: discoverContent
            }
        }
        .navigationTitle("Organizations")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showCreate = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("New organization")
            }
        }
        .task { await load() }
        .task(id: scope) {
            if scope == .discover && directory.isEmpty { await loadDirectory(reset: true) }
        }
        .sheet(isPresented: $showCreate, onDismiss: { Task { await load() } }) {
            CreateOrganizationView()
                .environmentObject(authState)
        }
    }

    @ViewBuilder
    private var mineContent: some View {
        if isLoading && organizations.isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error, organizations.isEmpty {
            ContentUnavailableView {
                Label("Unable to load", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            } actions: {
                Button("Retry") { Task { await load() } }
            }
        } else if organizations.isEmpty {
            ContentUnavailableView {
                Label("No Organizations", systemImage: "building.2")
            } description: {
                Text("Create an organization, or join a public one from Discover.")
            } actions: {
                Button("Create Organization") { showCreate = true }
                Button("Browse public organizations") { scope = .discover }
            }
        } else {
            List(organizations) { org in
                NavigationLink {
                    OrganizationDetailView(orgId: org.id, initialName: org.name)
                        .environmentObject(authState)
                } label: {
                    OrganizationRow(org: org)
                }
            }
        }
    }

    @ViewBuilder
    private var discoverContent: some View {
        if isLoadingDirectory && directory.isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let directoryError, directory.isEmpty {
            ContentUnavailableView {
                Label("Unable to load", systemImage: "exclamationmark.triangle")
            } description: {
                Text(directoryError)
            } actions: {
                Button("Retry") { Task { await loadDirectory(reset: true) } }
            }
        } else if directory.isEmpty {
            ContentUnavailableView {
                Label("No Public Organizations", systemImage: "building.2")
            } description: {
                Text("There are no public organizations to join yet.")
            }
        } else {
            List {
                if let joinError {
                    Section { Text(joinError).font(.ilMono()).foregroundStyle(.red) }
                }
                ForEach(directory) { org in
                    DirectoryRow(
                        org: org,
                        isJoining: joiningId == org.id,
                        canJoin: canJoin(org),
                        onJoin: { Task { await join(org) } }
                    )
                }
                if let pagination = directoryPagination, pagination.hasMore, !isLoadingDirectory {
                    HStack { Spacer(); ProgressView(); Spacer() }
                        .onAppear { Task { await loadDirectory(reset: false) } }
                }
            }
            .listStyle(.plain)
        }
    }

    /// Only public orgs the viewer isn't already in. `POST /api/user/organizations`
    /// rejects private orgs outright and conflicts on an existing membership.
    private func canJoin(_ org: Organization) -> Bool {
        org.isPublic == true && org.role == nil
    }

    private func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            organizations = try await APIClient.shared.userOrganizations()
        } catch APIError.status(401) {
            authState.handleUnauthorized()
        } catch {
            self.error = "Could not load organizations."
        }
    }

    private func loadDirectory(reset: Bool) async {
        if reset { directoryPagination = nil }
        guard !isLoadingDirectory else { return }
        isLoadingDirectory = true
        directoryError = nil
        defer { isLoadingDirectory = false }
        let offset = reset ? 0 : directory.count
        do {
            let result = try await APIClient.shared.publicOrganizations(limit: pageSize, offset: offset)
            if reset {
                directory = result.orgs
            } else {
                directory.append(contentsOf: result.orgs)
            }
            directoryPagination = result.pagination
        } catch APIError.status(401) {
            authState.handleUnauthorized()
        } catch {
            self.directoryError = "Could not load public organizations."
        }
    }

    private func join(_ org: Organization) async {
        joiningId = org.id
        joinError = nil
        defer { joiningId = nil }
        do {
            try await APIClient.shared.joinOrganization(organizationId: org.id)
            await load()
            await loadDirectory(reset: true)
        } catch APIError.status(401) {
            authState.handleUnauthorized()
        } catch APIError.forbidden(_) {
            joinError = "You can't join this organization."
        } catch APIError.conflict(let message) {
            joinError = message
        } catch APIError.server(let message) {
            joinError = message
        } catch {
            joinError = "Could not join this organization."
        }
    }
}

/// A directory row: the org, its size, and either a Join action or the viewer's
/// existing role.
private struct DirectoryRow: View {
    let org: Organization
    let isJoining: Bool
    let canJoin: Bool
    let onJoin: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "building.2.fill")
                .foregroundStyle(.secondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(org.name).font(.ilBody())
                if let description = org.description, !description.isEmpty {
                    Text(description)
                        .font(.ilBody(13))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if let count = org.memberCount {
                    Text("\(count) member\(count == 1 ? "" : "s")")
                        .font(.ilMono())
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if isJoining {
                ProgressView()
            } else if canJoin {
                Button("Join", action: onJoin)
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Join \(org.name)")
            } else if let role = org.role {
                Text(role.label)
                    .font(.ilMono())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(ILColor.surface2)
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, 2)
    }
}

private struct OrganizationRow: View {
    let org: Organization

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "building.2.fill")
                .foregroundStyle(.secondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(org.name).font(.ilBody())
                if let role = org.role {
                    Text(role.label).font(.ilMono()).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let count = org.memberCount {
                Text("\(count)")
                    .font(.ilMono())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Detail

struct OrganizationDetailView: View {
    let orgId: String
    var initialName: String?

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authState: AuthState
    @State private var org: Organization?
    @State private var isLoading = true
    @State private var error: String?
    @State private var showEdit = false
    @State private var showDeleteConfirm = false
    @State private var actionError: String?

    private var myRole: OrgRole? { org?.role }
    private var isOwner: Bool { myRole == .owner }

    var body: some View {
        List {
            if let actionError {
                Section { Text(actionError).font(.ilMono()).foregroundStyle(.red) }
            }
            if let org {
                Section {
                    if let desc = org.description, !desc.isEmpty {
                        Text(desc)
                    }
                    LabeledContent("Visibility", value: org.isPublic == true ? "Public" : "Private")
                    if let count = org.memberCount {
                        LabeledContent("Members", value: "\(count)")
                    }
                    if let role = org.role {
                        LabeledContent("Your role", value: role.label)
                    }
                }
                Section {
                    NavigationLink {
                        OrganizationMembersView(orgId: orgId, myRole: myRole)
                            .environmentObject(authState)
                    } label: {
                        Label("Members", systemImage: "person.3")
                    }
                }
                if isOwner {
                    Section {
                        Button {
                            showEdit = true
                        } label: {
                            Label("Edit organization", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Label("Delete organization", systemImage: "trash")
                        }
                    }
                }
            } else if isLoading {
                ProgressView()
            } else if let error {
                ContentUnavailableView {
                    Label("Unable to load", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Retry") { Task { await load() } }
                }
            }
        }
        .navigationTitle(org?.name ?? initialName ?? "Organization")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .sheet(isPresented: $showEdit, onDismiss: { Task { await load() } }) {
            if let org {
                EditOrganizationView(org: org)
                    .environmentObject(authState)
            }
        }
        .confirmationDialog("Delete this organization?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { Task { await delete() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes the organization for all members.")
        }
    }

    private func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            org = try await APIClient.shared.organization(id: orgId)
        } catch APIError.status(401) {
            authState.handleUnauthorized()
        } catch {
            self.error = "Could not load this organization."
        }
    }

    private func delete() async {
        actionError = nil
        do {
            try await APIClient.shared.deleteOrganization(id: orgId)
            dismiss()
        } catch APIError.server(let msg) {
            actionError = msg
        } catch {
            actionError = "Could not delete the organization."
        }
    }
}

// MARK: - Members

struct OrganizationMembersView: View {
    let orgId: String
    let myRole: OrgRole?

    @EnvironmentObject private var authState: AuthState
    @State private var members: [OrganizationMember] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var actionError: String?
    @State private var showAdd = false
    /// Cleared when the candidate search answers 403. That route is owner-only
    /// while `canManageMembers` also admits admins, so an admin only learns of
    /// the gate by hitting it — at which point the affordance disappears rather
    /// than reporting a failure they can do nothing about.
    @State private var searchAllowed = true

    private var ownerCount: Int { members.filter { $0.orgRole == .owner }.count }

    /// Owners and admins can manage members at all.
    private var canManageMembers: Bool {
        guard let myRole else { return false }
        return myRole >= .admin
    }

    private var canAddMembers: Bool { canManageMembers && searchAllowed }

    /// The last remaining owner can't be changed, and admins can't manage owners.
    private func canManage(_ member: OrganizationMember) -> Bool {
        guard canManageMembers, let myRole else { return false }
        if member.orgRole == .owner && ownerCount <= 1 { return false }
        if member.orgRole == .owner && myRole != .owner { return false }
        return true
    }

    var body: some View {
        Group {
            if isLoading && members.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error, members.isEmpty {
                ContentUnavailableView {
                    Label("Unable to load", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Retry") { Task { await load() } }
                }
            } else {
                List {
                    if let actionError {
                        Section { Text(actionError).font(.ilMono()).foregroundStyle(.red) }
                    }
                    ForEach(members) { member in
                        MemberRow(
                            member: member,
                            canManage: canManage(member),
                            onChangeRole: { role in Task { await changeRole(member, to: role) } }
                        )
                        .swipeActions(edge: .trailing) {
                            if canManage(member) {
                                Button(role: .destructive) {
                                    Task { await remove(member) }
                                } label: {
                                    Label("Remove", systemImage: "person.fill.xmark")
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Members")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if canAddMembers {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "person.badge.plus") }
                        .accessibilityLabel("Add member")
                }
            }
        }
        .task { await load() }
        .sheet(isPresented: $showAdd) {
            AddOrganizationMemberView(
                orgId: orgId,
                existingMemberIds: members.map(\.id),
                onForbidden: { searchAllowed = false },
                onAdded: { Task { await load() } }
            )
            .environmentObject(authState)
        }
    }

    private func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let (list, _) = try await APIClient.shared.organizationMembers(id: orgId)
            members = list
        } catch APIError.status(401) {
            authState.handleUnauthorized()
        } catch {
            self.error = "Could not load members."
        }
    }

    private func changeRole(_ member: OrganizationMember, to role: OrgRole) async {
        guard member.orgRole != role else { return }
        actionError = nil
        do {
            try await APIClient.shared.setOrganizationMemberRole(id: orgId, userId: member.id, role: role)
            await load()
        } catch APIError.server(let msg) {
            actionError = msg
        } catch {
            actionError = "Could not change role."
        }
    }

    private func remove(_ member: OrganizationMember) async {
        actionError = nil
        do {
            try await APIClient.shared.removeOrganizationMember(id: orgId, userId: member.id)
            members.removeAll { $0.id == member.id }
        } catch APIError.server(let msg) {
            actionError = msg
        } catch {
            actionError = "Could not remove this member."
        }
    }
}

private struct MemberRow: View {
    let member: OrganizationMember
    let canManage: Bool
    let onChangeRole: (OrgRole) -> Void

    var body: some View {
        HStack(spacing: 12) {
            avatar
            VStack(alignment: .leading, spacing: 2) {
                Text(member.displayNameOrUsername).font(.ilBody())
                Text("@\(member.username)").font(.ilMono()).foregroundStyle(.secondary)
            }
            Spacer()
            if canManage {
                Menu {
                    ForEach(OrgRole.allCases, id: \.self) { role in
                        Button {
                            onChangeRole(role)
                        } label: {
                            if member.orgRole == role {
                                Label(role.label, systemImage: "checkmark")
                            } else {
                                Text(role.label)
                            }
                        }
                    }
                } label: {
                    roleBadge
                }
            } else {
                roleBadge
            }
        }
        .padding(.vertical, 2)
    }

    private var roleBadge: some View {
        Text((member.orgRole ?? .member).label)
            .font(.ilMono())
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(ILColor.surface2)
            .clipShape(Capsule())
    }

    @ViewBuilder
    private var avatar: some View {
        if let url = member.avatar.flatMap({ URL(string: $0) }) {
            AsyncImage(url: url) { phase in
                if let image = phase.image { image.resizable().scaledToFill() }
                else { Image(systemName: "person.circle.fill").resizable().scaledToFit().foregroundStyle(.secondary) }
            }
            .frame(width: 36, height: 36)
            .clipShape(Circle())
        } else {
            Image(systemName: "person.circle.fill")
                .resizable().scaledToFit().frame(width: 36, height: 36)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Add member

/// Owner-only search over users who aren't in the org yet, with the role they'll
/// join as. The backing route is gated more tightly than this view's entry point
/// (owners only, not admins), so a 403 retires the affordance via `onForbidden`
/// instead of showing an error the viewer can't act on.
private struct AddOrganizationMemberView: View {
    let orgId: String
    let existingMemberIds: [String]
    let onForbidden: () -> Void
    let onAdded: () -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authState: AuthState
    @State private var role: OrgRole = .member
    @State private var query = ""
    @State private var candidates: [OrganizationUser] = []
    @State private var isLoading = false
    @State private var error: String?
    @State private var addingId: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Role") {
                    Picker("Role", selection: $role) {
                        ForEach(OrgRole.allCases, id: \.self) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel("Role for the new member")
                }

                Section("People") {
                    TextField("Search by name or username", text: $query)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityLabel("Search people to add")
                        .onSubmit { Task { await loadCandidates() } }

                    if isLoading {
                        ProgressView()
                    } else if let error {
                        Text(error).font(.ilMono()).foregroundStyle(.red)
                    } else if candidates.isEmpty {
                        Text(query.trimmingCharacters(in: .whitespaces).isEmpty ? "No people available to add." : "No matching people.")
                            .font(.ilBody(15)).foregroundStyle(.secondary)
                    } else {
                        ForEach(candidates) { candidate in
                            Button {
                                Task { await add(candidate) }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(candidate.displayNameOrUsername).foregroundStyle(.primary)
                                        Text("@\(candidate.username)").font(.ilMono()).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if addingId == candidate.id {
                                        ProgressView()
                                    } else {
                                        Image(systemName: "plus.circle").foregroundStyle(ILColor.primary)
                                    }
                                }
                            }
                            .disabled(addingId != nil)
                        }
                    }
                }
            }
            .navigationTitle("Add Member")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task { await loadCandidates() }
            .onChange(of: query) { _, newValue in
                Task { await debouncedSearch(for: newValue) }
            }
        }
    }

    private func debouncedSearch(for value: String) async {
        try? await Task.sleep(nanoseconds: 300_000_000)
        guard value == query else { return }
        await loadCandidates()
    }

    private func loadCandidates() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        do {
            candidates = try await APIClient.shared.organizationUsers(
                id: orgId,
                search: trimmed.isEmpty ? nil : trimmed,
                excludeMembers: existingMemberIds.isEmpty ? nil : existingMemberIds
            )
        } catch APIError.status(401) {
            authState.handleUnauthorized()
        } catch APIError.forbidden(_) {
            onForbidden()
            dismiss()
        } catch APIError.status(403) {
            onForbidden()
            dismiss()
        } catch {
            self.error = "Could not load people."
        }
    }

    private func add(_ candidate: OrganizationUser) async {
        addingId = candidate.id
        defer { addingId = nil }
        do {
            try await APIClient.shared.addOrganizationMember(id: orgId, userId: candidate.id, role: role)
            onAdded()
            dismiss()
        } catch APIError.status(401) {
            authState.handleUnauthorized()
        } catch APIError.forbidden(_) {
            self.error = "You can't add members to this organization."
        } catch APIError.server(let message) {
            self.error = message
        } catch {
            self.error = "Could not add this person."
        }
    }
}

// MARK: - Create / Edit

struct CreateOrganizationView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authState: AuthState
    @State private var name = ""
    @State private var description = ""
    @State private var isPublic = false
    @State private var isLoading = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Organization name", text: $name)
                }
                Section("Description") {
                    TextField("Description (optional)", text: $description, axis: .vertical)
                        .lineLimit(2...5)
                }
                Section {
                    Toggle("Public", isOn: $isPublic)
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red).font(.ilMono()) }
                }
            }
            .navigationTitle("New Organization")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { Task { await create() } }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
                }
            }
        }
    }

    private func create() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let desc = description.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            _ = try await APIClient.shared.createOrganization(name: trimmed, description: desc.isEmpty ? nil : desc, isPublic: isPublic)
            dismiss()
        } catch APIError.server(let msg) {
            error = msg
        } catch {
            self.error = "Could not create the organization."
        }
    }
}

struct EditOrganizationView: View {
    let org: Organization

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authState: AuthState
    @State private var name: String
    @State private var description: String
    @State private var isPublic: Bool
    @State private var isLoading = false
    @State private var error: String?

    init(org: Organization) {
        self.org = org
        _name = State(initialValue: org.name)
        _description = State(initialValue: org.description ?? "")
        _isPublic = State(initialValue: org.isPublic ?? false)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Organization name", text: $name)
                }
                Section("Description") {
                    TextField("Description (optional)", text: $description, axis: .vertical)
                        .lineLimit(2...5)
                }
                Section {
                    Toggle("Public", isOn: $isPublic)
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red).font(.ilMono()) }
                }
            }
            .navigationTitle("Edit Organization")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
                }
            }
        }
    }

    private func save() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let desc = description.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try await APIClient.shared.updateOrganization(id: org.id, name: trimmed, description: desc, isPublic: isPublic)
            dismiss()
        } catch APIError.server(let msg) {
            error = msg
        } catch {
            self.error = "Could not save changes."
        }
    }
}

#Preview {
    NavigationStack {
        OrganizationsListView()
            .environmentObject(AuthState())
    }
}
