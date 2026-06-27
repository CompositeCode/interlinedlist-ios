//
//  WatchersListView.swift
//  InterlinedList
//

import SwiftUI

/// Manager view of a list's watchers: see roles, change them, remove members,
/// and add new watchers/collaborators/managers. Presented from a list the
/// current user owns (and is therefore a manager of).
struct WatchersListView: View {
    let listId: String

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authState: AuthState
    @State private var watchers: [ListWatcher] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var actionError: String?
    @State private var showAdd = false

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && watchers.isEmpty {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error, watchers.isEmpty {
                    ContentUnavailableView {
                        Label("Unable to load", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Retry") { Task { await load() } }
                    }
                } else {
                    watchersList
                }
            }
            .navigationTitle("Watchers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "person.badge.plus") }
                        .accessibilityLabel("Add watcher")
                }
            }
            .task { await load() }
            .sheet(isPresented: $showAdd, onDismiss: { Task { await load() } }) {
                AddWatcherView(listId: listId)
                    .environmentObject(authState)
            }
        }
    }

    @ViewBuilder
    private var watchersList: some View {
        List {
            if let actionError {
                Section { Text(actionError).font(.caption).foregroundStyle(.red) }
            }
            if watchers.isEmpty {
                ContentUnavailableView {
                    Label("No watchers yet", systemImage: "eye")
                } description: {
                    Text("Add people to share this list with.")
                }
            } else {
                ForEach(watchers) { watcher in
                    WatcherRow(
                        watcher: watcher,
                        onChangeRole: { role in Task { await changeRole(watcher, to: role) } }
                    )
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            Task { await remove(watcher) }
                        } label: {
                            Label("Remove", systemImage: "person.fill.xmark")
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
            watchers = try await APIClient.shared.listWatchers(listId: listId)
        } catch APIError.status(401) {
            authState.handleUnauthorized()
        } catch {
            self.error = "Could not load watchers."
        }
    }

    private func changeRole(_ watcher: ListWatcher, to role: WatcherRole) async {
        guard watcher.watcherRole != role else { return }
        actionError = nil
        do {
            _ = try await APIClient.shared.setWatcherRole(listId: listId, userId: watcher.userId, role: role)
            await load()
        } catch APIError.server(let msg) {
            actionError = msg
        } catch {
            actionError = "Could not change role."
        }
    }

    private func remove(_ watcher: ListWatcher) async {
        actionError = nil
        do {
            try await APIClient.shared.removeWatcher(listId: listId, userId: watcher.userId)
            watchers.removeAll { $0.id == watcher.id }
        } catch APIError.server(let msg) {
            actionError = msg
        } catch {
            actionError = "Could not remove this person."
        }
    }
}

private struct WatcherRow: View {
    let watcher: ListWatcher
    let onChangeRole: (WatcherRole) -> Void

    var body: some View {
        HStack(spacing: 12) {
            avatar
            VStack(alignment: .leading, spacing: 2) {
                Text(watcher.user?.displayNameOrUsername ?? "User")
                    .font(.body)
                if let username = watcher.user?.username {
                    Text("@\(username)").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Menu {
                ForEach(WatcherRole.allCases, id: \.self) { role in
                    Button {
                        onChangeRole(role)
                    } label: {
                        if watcher.watcherRole == role {
                            Label(role.label, systemImage: "checkmark")
                        } else {
                            Text(role.label)
                        }
                    }
                }
            } label: {
                Text((watcher.watcherRole ?? .watcher).label)
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color(.secondarySystemFill))
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var avatar: some View {
        if let url = watcher.user?.avatar.flatMap({ URL(string: $0) }) {
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

/// Search for and add a new watcher with a chosen role.
private struct AddWatcherView: View {
    let listId: String

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authState: AuthState
    @State private var role: WatcherRole = .watcher
    @State private var candidates: [WatcherCandidate] = []
    @State private var isLoading = false
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
                    Text(role.detail).font(.caption).foregroundStyle(.secondary)
                }

                Section("People") {
                    if isLoading {
                        ProgressView()
                    } else if let error {
                        Text(error).font(.caption).foregroundStyle(.red)
                    } else if candidates.isEmpty {
                        Text("No people available to add.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    } else {
                        ForEach(candidates) { candidate in
                            Button {
                                Task { await add(candidate) }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(candidate.displayNameOrUsername).foregroundStyle(.primary)
                                        Text("@\(candidate.username)").font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if addingId == candidate.id {
                                        ProgressView()
                                    } else {
                                        Image(systemName: "plus.circle").foregroundStyle(Color.accentColor)
                                    }
                                }
                            }
                            .disabled(addingId != nil)
                        }
                    }
                }
            }
            .navigationTitle("Add Watcher")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task { await loadCandidates() }
        }
    }

    private func loadCandidates() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            candidates = try await APIClient.shared.searchWatcherCandidates(listId: listId)
        } catch APIError.status(401) {
            authState.handleUnauthorized()
        } catch {
            self.error = "Could not load people."
        }
    }

    private func add(_ candidate: WatcherCandidate) async {
        addingId = candidate.id
        defer { addingId = nil }
        do {
            _ = try await APIClient.shared.addWatcher(listId: listId, userId: candidate.id, role: role)
            dismiss()
        } catch APIError.server(let msg) {
            self.error = msg
        } catch {
            self.error = "Could not add this person."
        }
    }
}

#Preview {
    WatchersListView(listId: "list-1")
        .environmentObject(AuthState())
}
