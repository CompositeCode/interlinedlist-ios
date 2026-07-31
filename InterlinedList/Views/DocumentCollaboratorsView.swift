//
//  DocumentCollaboratorsView.swift
//  InterlinedList
//

import SwiftUI

/// Owner view of a document's per-person collaborators: see roles, change them,
/// remove people, and add new ones by search. Adding and role changes are
/// subscriber-gated (hidden for free users); listing and removing are always
/// available to the owner.
struct DocumentCollaboratorsView: View {
    let documentId: String

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authState: AuthState
    @State private var collaborators: [DocumentCollaborator] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var actionError: String?
    @State private var showAdd = false

    private var canManage: Bool { authState.user?.isSubscriber == true }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && collaborators.isEmpty {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error, collaborators.isEmpty {
                    ContentUnavailableView {
                        Label("Unable to load", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Retry") { Task { await load() } }
                    }
                } else {
                    collaboratorsList
                }
            }
            .navigationTitle("Collaborators")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                if canManage {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showAdd = true } label: { Image(systemName: "person.badge.plus") }
                            .accessibilityLabel("Add collaborator")
                    }
                }
            }
            .task { await load() }
            .sheet(isPresented: $showAdd, onDismiss: { Task { await load() } }) {
                AddDocumentCollaboratorView(documentId: documentId)
                    .environmentObject(authState)
            }
        }
    }

    @ViewBuilder
    private var collaboratorsList: some View {
        List {
            if let actionError {
                Section { Text(actionError).font(.ilMono()).foregroundStyle(.red) }
            }
            if collaborators.isEmpty {
                ContentUnavailableView {
                    Label("No collaborators yet", systemImage: "person.2")
                } description: {
                    Text("Add people to collaborate on this document.")
                }
            } else {
                ForEach(collaborators) { collaborator in
                    DocumentCollaboratorRow(
                        collaborator: collaborator,
                        canManage: canManage,
                        onChangeRole: { role in Task { await changeRole(collaborator, to: role) } }
                    )
                    .swipeActions(edge: .trailing) {
                        if canManage {
                            Button(role: .destructive) {
                                Task { await remove(collaborator) }
                            } label: {
                                Label("Remove", systemImage: "person.fill.xmark")
                            }
                        }
                    }
                }
            }
        }
    }

    private func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            collaborators = try await APIClient.shared.documentCollaborators(id: documentId)
        } catch APIError.status(401) {
            authState.handleUnauthorized()
        } catch {
            self.error = "Could not load collaborators."
        }
    }

    private func changeRole(_ collaborator: DocumentCollaborator, to role: WatcherRole) async {
        guard collaborator.collaboratorRole != role else { return }
        actionError = nil
        do {
            _ = try await APIClient.shared.setDocumentCollaboratorRole(id: documentId, userId: collaborator.userId, role: role)
            await load()
        } catch APIError.status(401) {
            authState.handleUnauthorized()
        } catch APIError.server(let msg) {
            actionError = msg
        } catch {
            actionError = "Could not change role."
        }
    }

    private func remove(_ collaborator: DocumentCollaborator) async {
        actionError = nil
        do {
            try await APIClient.shared.removeDocumentCollaborator(id: documentId, userId: collaborator.userId)
            collaborators.removeAll { $0.userId == collaborator.userId }
        } catch APIError.status(401) {
            authState.handleUnauthorized()
        } catch APIError.server(let msg) {
            actionError = msg
        } catch {
            actionError = "Could not remove this person."
        }
    }
}

private struct DocumentCollaboratorRow: View {
    let collaborator: DocumentCollaborator
    let canManage: Bool
    let onChangeRole: (WatcherRole) -> Void

    var body: some View {
        HStack(spacing: 12) {
            avatar
            VStack(alignment: .leading, spacing: 2) {
                Text(collaborator.displayNameOrUsername)
                    .font(.ilBody())
                if let username = collaborator.username {
                    Text("@\(username)").font(.ilMono()).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if canManage {
                Menu {
                    ForEach(WatcherRole.allCases, id: \.self) { role in
                        Button {
                            onChangeRole(role)
                        } label: {
                            if collaborator.collaboratorRole == role {
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
        Text((collaborator.collaboratorRole ?? .watcher).label)
            .font(.ilMono())
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(ILColor.surface2)
            .clipShape(Capsule())
    }

    @ViewBuilder
    private var avatar: some View {
        if let url = collaborator.avatar.flatMap({ URL(string: $0) }) {
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

/// Search for and add a new collaborator with a chosen role.
private struct AddDocumentCollaboratorView: View {
    let documentId: String

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authState: AuthState
    @State private var role: WatcherRole = .watcher
    @State private var query = ""
    @State private var candidates: [WatcherCandidate] = []
    @State private var isSearching = false
    @State private var error: String?
    @State private var addingId: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Role") {
                    Picker("Role", selection: $role) {
                        ForEach(WatcherRole.allCases, id: \.self) { r in
                            Text(r.label).tag(r)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text(role.detail).font(.ilMono()).foregroundStyle(.secondary)
                }

                Section("People") {
                    TextField("Search by name or username", text: $query)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityLabel("Search people to add")
                        .onSubmit { Task { await search() } }

                    if isSearching {
                        ProgressView()
                    } else if let error {
                        Text(error).font(.ilMono()).foregroundStyle(.red)
                    } else if candidates.isEmpty {
                        Text(query.isEmpty ? "Type to search for people." : "No matching people.")
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
            .navigationTitle("Add Collaborator")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onChange(of: query) { _, newValue in
                Task { await debouncedSearch(for: newValue) }
            }
        }
    }

    private func debouncedSearch(for value: String) async {
        try? await Task.sleep(nanoseconds: 300_000_000)
        guard value == query else { return }
        await search()
    }

    private func search() async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            candidates = []
            return
        }
        isSearching = true
        error = nil
        defer { isSearching = false }
        do {
            candidates = try await APIClient.shared.searchDocumentCollaboratorCandidates(id: documentId, query: trimmed)
        } catch APIError.status(401) {
            authState.handleUnauthorized()
        } catch {
            self.error = "Could not search people."
        }
    }

    private func add(_ candidate: WatcherCandidate) async {
        addingId = candidate.id
        defer { addingId = nil }
        do {
            _ = try await APIClient.shared.addDocumentCollaborator(id: documentId, userId: candidate.id, role: role)
            dismiss()
        } catch APIError.status(401) {
            authState.handleUnauthorized()
        } catch APIError.server(let msg) {
            self.error = msg
        } catch {
            self.error = "Could not add this person."
        }
    }
}

#Preview {
    DocumentCollaboratorsView(documentId: "doc-1")
        .environmentObject(AuthState())
}
