//
//  CreateListView.swift
//  InterlinedList
//

import SwiftUI

struct CreateListView: View {
    let onCreate: (UserList) -> Void

    @EnvironmentObject private var authState: AuthState
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var description = ""
    @State private var isPublic = true
    @State private var columns: [DraftProperty] = ListSchemaDraft.starterColumns()
    @State private var isLoading = false
    @State private var errorMessage: String?

    @State private var githubBacked = false
    @State private var repos: [GitHubRepo] = []
    @State private var selectedRepo: String?
    @State private var reposLoading = false
    @State private var reposError: String?
    @State private var reposLoaded = false

    private var isSubscriber: Bool { authState.user?.isSubscriber == true }
    private var hasGitHubIdentity: Bool { authState.hasGitHubIdentity }
    private var canOfferGitHub: Bool { isSubscriber && hasGitHubIdentity }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canCreate: Bool {
        guard !isLoading, !trimmedName.isEmpty else { return false }
        if githubBacked {
            return selectedRepo?.contains("/") == true
        }
        return ListSchemaDraft.hasCreatableColumns(columns)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    TextField("Description (optional)", text: $description)
                    Toggle("Public", isOn: $isPublic)
                }

                githubSection

                if !githubBacked {
                    columnsSection
                }

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.ilMono())
                    }
                }

                Section {
                    Button {
                        Task { await create() }
                    } label: {
                        HStack {
                            if isLoading {
                                ProgressView()
                                    .frame(width: 20, height: 20)
                            }
                            Text("Create")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(!canCreate)
                }
            }
            .navigationTitle("New List")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task {
                if isSubscriber { await authState.loadLinkedProvidersIfNeeded() }
            }
        }
    }

    // MARK: - GitHub section

    @ViewBuilder
    private var githubSection: some View {
        if canOfferGitHub {
            Section {
                Toggle("GitHub-backed list", isOn: $githubBacked)
                    .accessibilityLabel("Create a GitHub-backed list")
                if githubBacked {
                    if reposLoading {
                        HStack { ProgressView(); Text("Loading repositories…").foregroundStyle(.secondary) }
                    } else if let reposError {
                        Text(reposError)
                            .foregroundStyle(.red)
                            .font(.ilMono())
                    } else if repos.isEmpty {
                        Text("No repositories found for your linked GitHub account.")
                            .foregroundStyle(.secondary)
                            .font(.ilMono())
                    } else {
                        Picker("Repository", selection: $selectedRepo) {
                            Text("Select a repository").tag(String?.none)
                            ForEach(repos) { repo in
                                Text(repo.fullName).tag(String?.some(repo.fullName))
                            }
                        }
                        .accessibilityLabel("GitHub repository")
                    }
                }
            } header: {
                Text("GitHub")
            } footer: {
                if githubBacked {
                    Text("Issues from the selected repository become this list's rows.")
                }
            }
            .onChange(of: githubBacked) { _, on in
                if on { Task { await loadReposIfNeeded() } }
            }
        } else if isSubscriber && !hasGitHubIdentity {
            Section {
                Text("Connect GitHub on the web to create GitHub-backed lists.")
                    .foregroundStyle(.secondary)
                    .font(.ilMono())
            } header: {
                Text("GitHub")
            }
        }
    }

    @ViewBuilder
    private var columnsSection: some View {
        Section {
            ForEach($columns) { $column in
                ColumnRow(column: $column, onDelete: {
                    columns.removeAll { $0.id == column.id }
                })
            }
            .onMove { from, to in
                columns.move(fromOffsets: from, toOffset: to)
            }
            Button {
                columns.append(DraftProperty.newBlank())
            } label: {
                Label("Add Column", systemImage: "plus")
            }
            .accessibilityLabel("Add column")
        } header: {
            HStack {
                Text("Columns")
                Spacer()
                if columns.count > 1 {
                    EditButton()
                        .font(.ilMono())
                }
            }
        } footer: {
            Text("Lists need at least one named column.")
        }
    }

    private func loadReposIfNeeded() async {
        guard !reposLoaded, !reposLoading else { return }
        reposLoading = true
        reposError = nil
        defer { reposLoading = false }
        do {
            let fetched = try await APIClient.shared.githubRepos()
            repos = fetched
            reposLoaded = true
            if selectedRepo == nil,
               let preferred = authState.user?.githubDefaultRepo,
               fetched.contains(where: { $0.fullName == preferred }) {
                selectedRepo = preferred
            }
        } catch APIError.status(401) {
            authState.handleUnauthorized()
            reposError = "Session expired. Please try again."
        } catch APIError.server(let msg) {
            reposError = msg
        } catch {
            reposError = "Couldn't load your GitHub repositories."
        }
    }

    private func create() async {
        errorMessage = nil
        guard !trimmedName.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        let trimmedDesc = description.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let list: UserList
            if githubBacked {
                guard let repo = selectedRepo, let source = Self.gitHubSource(from: repo) else {
                    errorMessage = "Select a repository."
                    return
                }
                list = try await APIClient.shared.createList(
                    title: trimmedName,
                    description: trimmedDesc.isEmpty ? nil : trimmedDesc,
                    isPublic: isPublic,
                    githubSource: source
                )
            } else {
                guard ListSchemaDraft.hasCreatableColumns(columns) else { return }
                let schema = ListSchemaDraft.dslSchema(name: trimmedName, columns)
                list = try await APIClient.shared.createList(
                    title: trimmedName,
                    description: trimmedDesc.isEmpty ? nil : trimmedDesc,
                    isPublic: isPublic,
                    schema: schema.fields.isEmpty ? nil : schema
                )
            }
            onCreate(list)
            dismiss()
        } catch APIError.status(401) {
            authState.handleUnauthorized()
            errorMessage = "Session expired. Please try again."
        } catch APIError.server(let msg) {
            errorMessage = msg
        } catch {
            errorMessage = "Failed to create list."
        }
    }

    private static func gitHubSource(from fullName: String) -> APIClient.GitHubSource? {
        guard let slash = fullName.firstIndex(of: "/") else { return nil }
        let owner = String(fullName[..<slash])
        let repo = String(fullName[fullName.index(after: slash)...])
        guard !owner.isEmpty, !repo.isEmpty else { return nil }
        return APIClient.GitHubSource(owner: owner, repo: repo)
    }
}

// MARK: - Column row (name + type)

private struct ColumnRow: View {
    @Binding var column: DraftProperty
    let onDelete: () -> Void

    var body: some View {
        HStack {
            TextField("Column name", text: $column.propertyName)
                .textInputAutocapitalization(.words)
                .accessibilityLabel("Column name")
            Picker("Type", selection: $column.propertyType) {
                ForEach(DraftProperty.supportedTypes, id: \.self) { t in
                    Text(t.capitalized).tag(t)
                }
            }
            .labelsHidden()
            .accessibilityLabel("Column type")
            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Delete column \(column.propertyName.isEmpty ? "untitled" : column.propertyName)")
        }
    }
}

#Preview {
    CreateListView(onCreate: { _ in })
        .environmentObject(AuthState())
        .environmentObject(AppDataStore())
}
