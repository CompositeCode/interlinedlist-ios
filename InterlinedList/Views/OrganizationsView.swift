//
//  OrganizationsView.swift
//  InterlinedList
//

import SwiftUI

/// The organizations the current user belongs to, with create / open actions.
struct OrganizationsListView: View {
    @EnvironmentObject private var authState: AuthState
    @State private var organizations: [Organization] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var showCreate = false

    var body: some View {
        Group {
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
                    Text("Create an organization to collaborate with others.")
                } actions: {
                    Button("Create Organization") { showCreate = true }
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
        .navigationTitle("Organizations")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showCreate = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("New organization")
            }
        }
        .task { await load() }
        .sheet(isPresented: $showCreate, onDismiss: { Task { await load() } }) {
            CreateOrganizationView()
                .environmentObject(authState)
        }
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
}

private struct OrganizationRow: View {
    let org: Organization

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "building.2.fill")
                .foregroundStyle(.secondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(org.name).font(.body)
                if let role = org.role {
                    Text(role.label).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let count = org.memberCount {
                Text("\(count)")
                    .font(.caption)
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
                Section { Text(actionError).font(.caption).foregroundStyle(.red) }
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

    private var ownerCount: Int { members.filter { $0.orgRole == .owner }.count }

    /// Owners and admins can manage. The last remaining owner can't be changed,
    /// and admins can't manage owners.
    private func canManage(_ member: OrganizationMember) -> Bool {
        guard let myRole, myRole >= .admin else { return false }
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
                        Section { Text(actionError).font(.caption).foregroundStyle(.red) }
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
        .task { await load() }
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
                Text(member.displayNameOrUsername).font(.body)
                Text("@\(member.username)").font(.caption).foregroundStyle(.secondary)
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
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color(.secondarySystemFill))
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
                    Section { Text(error).foregroundStyle(.red).font(.caption) }
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
                    Section { Text(error).foregroundStyle(.red).font(.caption) }
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
