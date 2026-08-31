//
//  ListsView.swift
//  InterlinedList
//

import SwiftUI

struct ListsView: View {
    @EnvironmentObject var authState: AuthState
    @EnvironmentObject var store: AppDataStore
    @State private var showCreateList = false
    @State private var createError: String?
    @State private var searchText = ""
    @State private var searchResults: [UserList] = []
    @State private var isSearching = false
    @State private var treeNodes: [ListTreeNode] = []

    private func rebuildTree() -> [ListTreeNode] {
        ListTreeNode.buildTree(lists: store.userLists)
    }

    var body: some View {
        NavigationStack {
            listContent
            .navigationTitle("Lists")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: UserList.self) { list in
                ListDetailView(list: list)
                    .environmentObject(authState)
            }
            .searchable(text: $searchText, prompt: "Search lists")
            .onSubmit(of: .search) {
                Task { await runSearch() }
            }
            .onChange(of: searchText) { _, newValue in
                if newValue.isEmpty {
                    searchResults = []
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { addMenu }
            }
            .sheet(isPresented: $showCreateList) {
                CreateListView { _ in
                    Task { await store.refreshLists() }
                }
                .environmentObject(authState)
                .environmentObject(store)
            }
            .refreshable {
                await store.refreshLists()
            }
            .onAppear { treeNodes = rebuildTree() }
            .onChange(of: store.userLists) { _, _ in treeNodes = rebuildTree() }
        }
    }

    @ViewBuilder
    private var listContent: some View {
        if !searchText.isEmpty {
            searchResultsList
        } else if store.listsLoading && treeNodes.isEmpty {
            ListSkeletonView()
        } else if let error = store.listsError, treeNodes.isEmpty {
            ContentUnavailableView {
                Label("Unable to load", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            } actions: {
                Button("Retry") { Task { await store.refreshLists() } }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if treeNodes.isEmpty {
            ContentUnavailableView {
                Label("No Lists", systemImage: "list.bullet.rectangle")
            } description: {
                Text("No lists found.")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(treeNodes) { node in
                    ListTreeNodeRow(
                        node: node,
                        onDeleteList: { list in Task { await deleteList(list) } },
                        onUpdateList: { _ in Task { await store.refreshLists() } }
                    )
                }
            }
            .listStyle(.sidebar)
        }
    }

    @ViewBuilder
    private var addMenu: some View {
        Menu {
            Button { showCreateList = true } label: {
                Label("New List", systemImage: "plus.rectangle")
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color(ILColor.primary))
                .frame(width: 34, height: 34)
                .background(Color(ILColor.primary).opacity(0.12))
                .clipShape(Circle())
        }
        .accessibilityLabel("New item")
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var searchResultsList: some View {
        if isSearching {
            ProgressView("Searching…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if searchResults.isEmpty {
            ContentUnavailableView.search(text: searchText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(searchResults) { list in
                NavigationLink(value: list) {
                    ListNameWithVisibility(name: list.name, isPublic: list.isPublic, isGitHubBacked: list.isGitHubBacked)
                }
            }
        }
    }

    private func runSearch() async {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        isSearching = true
        defer { isSearching = false }
        do {
            let (results, _) = try await APIClient.shared.searchLists(q: q)
            searchResults = results
        } catch APIError.status(401) {
            authState.handleUnauthorized()
        } catch {
            searchResults = []
        }
    }

    private func deleteList(_ list: UserList) async {
        do {
            try await APIClient.shared.deleteList(id: list.id)
            store.removeList(id: list.id)
        } catch APIError.status(401) {
            authState.handleUnauthorized()
        } catch {
            await store.refreshLists()
        }
    }
}

// MARK: - Rename list sheet

private struct RenameListView: View {
    let list: UserList
    let onSave: (UserList) -> Void

    @EnvironmentObject private var authState: AuthState
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var isPublic: Bool
    @State private var isLoading = false
    @State private var errorMessage: String?

    init(list: UserList, onSave: @escaping (UserList) -> Void) {
        self.list = list
        self.onSave = onSave
        _title = State(initialValue: list.name)
        _isPublic = State(initialValue: list.isPublic ?? false)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("List name", text: $title)
                }
                Section {
                    Toggle("Public", isOn: $isPublic)
                }
                if let error = errorMessage {
                    Section {
                        Text(error).foregroundStyle(.red).font(.ilMono())
                    }
                }
            }
            .navigationTitle("Edit List")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { Task { await save() } }
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
                }
            }
        }
    }

    private func save() async {
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let updated = try await APIClient.shared.updateList(
                id: list.id,
                title: trimmed,
                description: list.description,
                isPublic: isPublic
            )
            onSave(updated)
            dismiss()
        } catch APIError.status(401) {
            authState.handleUnauthorized()
            errorMessage = "Session expired. Please try again."
        } catch APIError.server(let msg) {
            errorMessage = msg
        } catch {
            errorMessage = "Failed to update list."
        }
    }
}

// MARK: - Tree row

struct ListTreeNodeRow: View {
    let node: ListTreeNode
    let onDeleteList: (UserList) -> Void
    let onUpdateList: (UserList) -> Void
    @State private var isExpanded = true
    @State private var showRename = false
    @State private var schemaEditorList: UserList?
    @State private var schemaEditorSchema: [ListPropertyDef] = []
    @State private var isLoadingSchema = false

    var body: some View {
        if let children = node.children, let list = node.list {
            DisclosureGroup(isExpanded: $isExpanded) {
                ForEach(children) { child in
                    ListTreeNodeRow(node: child, onDeleteList: onDeleteList, onUpdateList: onUpdateList)
                }
            } label: {
                NavigationLink(value: list) {
                    ListNameWithVisibility(name: node.name, isPublic: list.isPublic, isGitHubBacked: list.isGitHubBacked)
                }
                .contextMenu {
                    Button("Rename / Edit") { showRename = true }
                    Button("Edit Schema") { Task { await openSchemaEditor(for: list) } }
                    Button("Delete", role: .destructive) { onDeleteList(list) }
                }
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive) {
                    onDeleteList(list)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            .sheet(isPresented: $showRename) {
                RenameListView(list: list) { _ in onUpdateList(list) }
            }
            .sheet(item: $schemaEditorList) { editing in
                ListSchemaEditorView(list: editing, schema: schemaEditorSchema) { _ in onUpdateList(editing) }
            }
        } else if let list = node.list {
            NavigationLink(value: list) {
                ListNameWithVisibility(name: node.name, isPublic: list.isPublic, isGitHubBacked: list.isGitHubBacked)
            }
            .contextMenu {
                Button("Rename / Edit") { showRename = true }
                Button("Edit Schema") { Task { await openSchemaEditor(for: list) } }
                Button("Delete", role: .destructive) { onDeleteList(list) }
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive) {
                    onDeleteList(list)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                Button {
                    Task { await openSchemaEditor(for: list) }
                } label: {
                    Label("Schema", systemImage: "rectangle.3.group")
                }
                .tint(ILColor.primary)
            }
            .sheet(isPresented: $showRename) {
                RenameListView(list: list) { _ in onUpdateList(list) }
            }
            .sheet(item: $schemaEditorList) { editing in
                ListSchemaEditorView(list: editing, schema: schemaEditorSchema) { _ in onUpdateList(editing) }
            }
        }
    }

    private func openSchemaEditor(for list: UserList) async {
        guard !isLoadingSchema else { return }
        isLoadingSchema = true
        defer { isLoadingSchema = false }
        let schema = (try? await APIClient.shared.listSchema(listId: list.id)) ?? []
        schemaEditorSchema = schema
        schemaEditorList = list
    }
}

private struct ListNameWithVisibility: View {
    let name: String
    let isPublic: Bool?
    var isGitHubBacked: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            Text(name)
            if isGitHubBacked {
                Image("GitHubMark")
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .frame(width: 13, height: 13)
                    .foregroundStyle(Color.secondary)
                    .accessibilityLabel("GitHub-backed")
            }
            if isPublic == true {
                Image(systemName: "globe")
                    .font(.ilMono())
                    .foregroundStyle(ILColor.primary)
                    .accessibilityLabel("Public")
            } else {
                Image(systemName: "lock.fill")
                    .font(.ilMono())
                    .foregroundStyle(Color.secondary)
                    .accessibilityLabel("Private")
            }
        }
    }
}

// MARK: - List detail

struct ListDetailView: View {
    let list: UserList
    @EnvironmentObject var authState: AuthState
    @State private var schema: [ListPropertyDef] = []
    @State private var items: [ListItem] = []
    @State private var pendingUpdates: [String: [String: JSONValue]] = [:]
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var connections: [ListConnection] = []
    @State private var allLists: [UserList] = []
    @State private var showAddConnection = false
    @State private var addRelationshipRole: ListRelationship = .parent
    @State private var showAddItem = false
    @State private var editingItem: ListItem? = nil
    @State private var deletingItem: ListItem? = nil
    @State private var showDeleteConfirm = false
    @State private var showSharing = false
    @State private var isRefreshingGitHub = false
    @State private var gitHubRefreshError: String?
    @State private var gitHubStateFilter: GitHubStateFilter = .open

    /// Open/closed filter for GitHub-backed lists. GitHub issues carry a `state`
    /// of `open`/`closed`; the list defaults to showing open issues only.
    private enum GitHubStateFilter: String, CaseIterable, Identifiable {
        case open, closed
        var id: String { rawValue }
        var label: String { self == .open ? "Open" : "Closed" }
    }

    /// Watchers / share-links / invites are owner-only server-side. The lists tab
    /// is owner-scoped so this is true today, but gating on it keeps the
    /// management controls hidden should a shared-in list ever reach this view.
    private var isOwner: Bool { list.isOwned(by: authState.user?.id) }

    /// Fields shown in the add/edit form. GitHub-backed lists edit only
    /// title/body/state for v1 — read-only columns (#, url, timestamps) and the
    /// multiselect labels/assignees are excluded. Local lists use the full schema.
    private var formSchema: [ListPropertyDef] {
        guard list.isGitHubBacked else { return schema }
        return schema.filter { !$0.isReadOnly && $0.propertyType != "multiselect" }
    }

    /// Rows to render. Local lists show everything; GitHub-backed lists filter by
    /// the selected open/closed state (a row is closed only if `state == "closed"`).
    private var displayedItems: [ListItem] {
        guard list.isGitHubBacked else { return items }
        return items.filter { item in
            let isClosed = (item.rowData["state"]?.displayString ?? "open").lowercased() == "closed"
            return gitHubStateFilter == .closed ? isClosed : !isClosed
        }
    }

    private var emptyStateTitle: String {
        guard list.isGitHubBacked else { return "Empty List" }
        if items.isEmpty { return "No Issues" }
        return gitHubStateFilter == .open ? "No Open Issues" : "No Closed Issues"
    }

    private var emptyStateMessage: String {
        guard list.isGitHubBacked else { return "This list has no items yet." }
        if items.isEmpty { return "No issues synced from GitHub yet. Pull to refresh." }
        return gitHubStateFilter == .open
            ? "No open issues. Switch to Closed to see closed issues."
            : "No closed issues. Switch to Open to see open issues."
    }

    var body: some View {
        Group {
            if isLoading && items.isEmpty {
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage, items.isEmpty {
                ContentUnavailableView {
                    Label("Unable to load", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Retry") {
                        Task { await loadData() }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    if list.isGitHubBacked {
                        gitHubStatusSection
                        if !items.isEmpty {
                            gitHubStateFilterSection
                        }
                    }
                    if displayedItems.isEmpty && !isLoading {
                        ContentUnavailableView {
                            Label(emptyStateTitle, systemImage: "list.bullet")
                        } description: {
                            Text(emptyStateMessage)
                        }
                    } else {
                        ForEach(displayedItems) { item in
                            DynamicItemRow(
                                item: item,
                                schema: schema,
                                pendingUpdates: pendingUpdates[item.id] ?? [:],
                                isGitHubBacked: list.isGitHubBacked,
                                onUpdateField: { key, value in
                                    Task { await updateField(item: item, key: key, value: value) }
                                },
                                onEdit: {
                                    editingItem = item
                                },
                                onDelete: {
                                    deletingItem = item
                                    showDeleteConfirm = true
                                },
                                onSetState: list.isGitHubBacked ? { newState in
                                    Task { await setGitHubState(item: item, to: newState) }
                                } : nil
                            )
                        }
                    }
                    Section {
                        if connections.isEmpty {
                            Text("No parent or child lists yet")
                                .foregroundStyle(.secondary)
                                .font(.ilBody(15))
                        } else {
                            ForEach(connections) { conn in
                                let role = conn.relationship(relativeTo: list.id)
                                let otherListId = conn.otherListId(relativeTo: list.id)
                                let otherList = allLists.first { $0.id == otherListId }
                                let roleLabel = role == .parent ? "Parent" : "Child"
                                HStack {
                                    Image(systemName: role == .parent ? "arrow.up.forward.circle" : "arrow.down.forward.circle")
                                        .foregroundStyle(.secondary)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(otherList?.name ?? otherListId)
                                        Text(roleLabel)
                                            .font(.ilBody(13))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .accessibilityLabel("\(roleLabel) list: \(otherList?.name ?? otherListId)")
                            }
                            .onDelete { indexSet in
                                Task {
                                    for index in indexSet {
                                        let conn = connections[index]
                                        try? await APIClient.shared.deleteListConnection(id: conn.id)
                                        connections.remove(at: index)
                                    }
                                }
                            }
                        }
                    } header: {
                        HStack {
                            Text("Parents & Children")
                            Spacer()
                            Menu {
                                Button {
                                    addRelationshipRole = .parent
                                    showAddConnection = true
                                } label: {
                                    Label("Add Parent…", systemImage: "arrow.up")
                                }
                                Button {
                                    addRelationshipRole = .child
                                    showAddConnection = true
                                } label: {
                                    Label("Add Child…", systemImage: "arrow.down")
                                }
                            } label: {
                                Image(systemName: "plus")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Add a parent or child list")
                        }
                    }
                }
            }
        }
        .navigationTitle(list.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if list.isGitHubBacked {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await refreshGitHub() }
                    } label: {
                        if isRefreshingGitHub {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(isRefreshingGitHub)
                    .accessibilityLabel("Refresh from GitHub")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAddItem = true
                } label: {
                    Image(systemName: "plus")
                }
                .disabled(schema.isEmpty)
                .accessibilityLabel(list.isGitHubBacked ? "New issue" : "Add item to list")
            }
            if isOwner {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSharing = true
                    } label: {
                        Image(systemName: "person.2")
                    }
                    .accessibilityLabel("Share list")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                if let url = ILWebURL.list(list.id) {
                    SwiftUI.ShareLink(item: url) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Share link")
                }
            }
        }
        .task {
            await loadData()
        }
        .refreshable {
            await loadData()
        }
        .sheet(isPresented: $showSharing) {
            SharingView(kind: .lists, resourceId: list.id, title: list.name,
                        isPublic: list.isPublic ?? false) { newValue in
                _ = try await APIClient.shared.updateList(id: list.id, title: nil, description: nil, isPublic: newValue)
            }
            .environmentObject(authState)
        }
        .sheet(isPresented: $showAddConnection) {
            let role = addRelationshipRole
            let connectedIds = Set(connections.map { $0.otherListId(relativeTo: list.id) })
            let candidates = allLists.filter { $0.id != list.id && !connectedIds.contains($0.id) }
            NavigationStack {
                List {
                    if candidates.isEmpty {
                        Text("No other lists available to link.")
                            .foregroundStyle(.secondary)
                            .font(.ilBody(15))
                    } else {
                        ForEach(candidates) { candidate in
                            Button(candidate.name) {
                                Task {
                                    let fromId = role == .parent ? candidate.id : list.id
                                    let toId = role == .parent ? list.id : candidate.id
                                    if let conn = try? await APIClient.shared.createListConnection(
                                        fromListId: fromId,
                                        toListId: toId
                                    ) {
                                        connections.append(conn)
                                    }
                                    showAddConnection = false
                                }
                            }
                        }
                    }
                }
                .navigationTitle(role == .parent ? "Choose a Parent List" : "Choose a Child List")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showAddConnection = false }
                    }
                }
            }
        }
        .sheet(isPresented: $showAddItem) {
            ListItemFormView(schema: formSchema, existingItem: nil) { rowData in
                Task { await addItem(rowData: rowData) }
            }
        }
        .sheet(item: $editingItem) { item in
            ListItemFormView(schema: formSchema, existingItem: item) { rowData in
                Task { await saveEdit(item: item, rowData: rowData) }
            }
        }
        .confirmationDialog("Delete this item?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let item = deletingItem { Task { await deleteItem(item) } }
            }
            Button("Cancel", role: .cancel) { deletingItem = nil }
        }
    }

    @ViewBuilder
    private var gitHubStatusSection: some View {
        Section {
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.branch")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    if let repo = list.githubRepo {
                        Text(repo)
                            .font(.ilMono())
                    }
                    Text(gitHubStatusText)
                        .font(.ilBody(13))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isRefreshingGitHub {
                    ProgressView()
                }
            }
            if let gitHubRefreshError {
                Text(gitHubRefreshError)
                    .font(.ilMono())
                    .foregroundStyle(.red)
            } else if let metaError = list.githubMeta?.refreshError, !metaError.isEmpty {
                Text(metaError)
                    .font(.ilMono())
                    .foregroundStyle(.red)
            }
        } header: {
            Text("GitHub")
        }
    }

    @ViewBuilder
    private var gitHubStateFilterSection: some View {
        Section {
            Picker("Issue state", selection: $gitHubStateFilter) {
                ForEach(GitHubStateFilter.allCases) { filter in
                    Text(filter.label).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Filter issues by open or closed state")
        }
    }

    private var gitHubStatusText: String {
        let status = (list.githubMeta?.refreshStatus ?? "").lowercased()
        switch status {
        case "pending", "syncing":
            return "Syncing…"
        case "failed", "error":
            return "Last sync failed"
        default:
            if let refreshed = list.githubMeta?.lastRefreshedAt {
                return "Last refreshed \(Self.relativeDate(refreshed))"
            }
            return "Not yet refreshed"
        }
    }

    private static func relativeDate(_ iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = formatter.date(from: iso)
        if date == nil {
            formatter.formatOptions = [.withInternetDateTime]
            date = formatter.date(from: iso)
        }
        guard let date else { return iso }
        return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
    }

    private func refreshGitHub() async {
        guard !isRefreshingGitHub else { return }
        isRefreshingGitHub = true
        gitHubRefreshError = nil
        defer { isRefreshingGitHub = false }
        do {
            try await APIClient.shared.refreshList(id: list.id)
            await loadData()
        } catch APIError.status(401) {
            authState.handleUnauthorized()
        } catch APIError.server(let msg) {
            gitHubRefreshError = msg
        } catch {
            gitHubRefreshError = "Couldn't refresh from GitHub."
        }
    }

    private func addItem(rowData: [String: JSONValue]) async {
        do {
            let item = try await APIClient.shared.addListItem(listId: list.id, rowData: rowData)
            items.append(item)
        } catch APIError.status(401) {
            authState.handleUnauthorized()
        } catch {
        }
    }

    private func saveEdit(item: ListItem, rowData: [String: JSONValue]) async {
        do {
            let updated = try await APIClient.shared.updateItem(listId: list.id, itemId: item.id, rowData: rowData)
            if let idx = items.firstIndex(where: { $0.id == item.id }) {
                items[idx] = updated
            }
        } catch APIError.status(401) {
            authState.handleUnauthorized()
        } catch {
            await loadData()
        }
    }

    private func deleteItem(_ item: ListItem) async {
        do {
            try await APIClient.shared.deleteListItem(listId: list.id, itemId: item.id)
            items.removeAll { $0.id == item.id }
        } catch APIError.status(401) {
            authState.handleUnauthorized()
        } catch {
            await loadData()
        }
    }

    /// Flips a GitHub issue's state (open ⇄ closed). GitHub updates must carry the
    /// FULL row: the backend rebuilds the issue payload from the request alone and
    /// defaults a missing title to "Untitled", so a partial `{state}` would blank
    /// the title. Merge the new state into the existing row and send the whole row.
    private func setGitHubState(item: ListItem, to newState: String) async {
        var rowData = item.rowData
        rowData["state"] = .string(newState)
        do {
            let updated = try await APIClient.shared.updateItem(listId: list.id, itemId: item.id, rowData: rowData)
            if let idx = items.firstIndex(where: { $0.id == item.id }) {
                items[idx] = updated
            }
            // Refresh the issue list after a close/reopen so it reflects the new
            // state (and any GitHub-side changes) consistently, not just the one row.
            await loadData()
        } catch APIError.status(401) {
            authState.handleUnauthorized()
        } catch {
            await loadData()
        }
    }

    private func updateField(item: ListItem, key: String, value: JSONValue) async {
        pendingUpdates[item.id, default: [:]][key] = value
        do {
            let updated = try await APIClient.shared.updateRow(listId: list.id, itemId: item.id, key: key, value: value)
            if let idx = items.firstIndex(where: { $0.id == item.id }) {
                items[idx] = updated
            }
            pendingUpdates[item.id]?[key] = nil
        } catch APIError.status(401) {
            authState.handleUnauthorized()
            pendingUpdates[item.id]?[key] = nil
        } catch {
            pendingUpdates[item.id]?[key] = nil
        }
    }

    private func loadData() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            async let schemaTask = APIClient.shared.listSchema(listId: list.id)
            async let itemsTask = APIClient.shared.listItems(listId: list.id)
            async let connectionsTask = APIClient.shared.listConnections()
            async let allListsTask = APIClient.shared.lists()
            let (fetchedSchema, fetchedItems) = try await (schemaTask, itemsTask)
            // The server returns the synthetic issue schema for GitHub-backed
            // lists (backend fix). The client fallback is a safety net for an
            // older/undeployed backend or a transient empty response — without a
            // schema the add button is disabled and the add/edit form is empty.
            schema = (list.isGitHubBacked && fetchedSchema.isEmpty)
                ? ListPropertyDef.gitHubIssueSchema()
                : fetchedSchema
            items = fetchedItems
            pendingUpdates = [:]
            let listId = list.id
            connections = (try? await connectionsTask)?
                .filter { $0.fromListId == listId || $0.toListId == listId } ?? []
            allLists = (try? await allListsTask) ?? []
        } catch APIError.status(401) {
            authState.handleUnauthorized()
            errorMessage = "Session expired or not authorized."
        } catch APIError.server(let msg) {
            errorMessage = msg
        } catch {
            errorMessage = "Failed to load list."
        }
    }
}

// MARK: - Dynamic item row

struct DynamicItemRow: View {
    let item: ListItem
    let schema: [ListPropertyDef]
    let pendingUpdates: [String: JSONValue]
    var isGitHubBacked: Bool = false
    let onUpdateField: (String, JSONValue) -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    /// GitHub rows expose Close/Reopen instead of Delete; the callback flips the
    /// issue state via a full-row update. `nil` for local lists.
    var onSetState: ((String) -> Void)? = nil
    @State private var isExpanded = false

    private var gitHubStateIsOpen: Bool {
        (item.rowData["state"]?.displayString ?? "open").lowercased() != "closed"
    }

    private var visibleProps: [ListPropertyDef] {
        schema.filter { $0.isVisible }.sorted { $0.displayOrder < $1.displayOrder }
    }

    /// The most meaningful column to headline the row (title/name-like), not just
    /// the first field — which is frequently an id, number, or timestamp.
    private var primaryProp: ListPropertyDef? {
        ListPropertyDef.primaryDisplayField(from: schema)
    }

    private var remainingProps: [ListPropertyDef] {
        guard let primary = primaryProp else { return [] }
        return visibleProps.filter { $0.id != primary.id }
    }

    /// Shown when there's no schema to pick a column from: prefer a title-like
    /// value over the alphabetically-first key (which is often an assignee/date).
    private var fallbackText: String {
        for key in ["title", "name", "subject", "summary"] {
            if let v = item.rowData[key]?.displayString, !v.isEmpty { return v }
        }
        if let first = item.rowData.sorted(by: { $0.key < $1.key }).first(where: { !$0.value.displayString.isEmpty }) {
            return first.value.displayString
        }
        return "—"
    }

    private func effectiveValue(for key: String) -> JSONValue {
        pendingUpdates[key] ?? item.rowData[key] ?? .null
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                if let prop = primaryProp {
                    FieldValueView(
                        value: effectiveValue(for: prop.propertyKey),
                        propertyType: prop.propertyType,
                        label: prop.propertyName,
                        showLabel: false,
                        onToggle: prop.propertyType == "boolean" ? { newVal in
                            onUpdateField(prop.propertyKey, newVal)
                        } : nil
                    )
                } else {
                    Text(fallbackText)
                        .foregroundStyle(.primary)
                }
                Spacer()
                if !remainingProps.isEmpty {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
                    } label: {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.ilMono())
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(isExpanded ? "Collapse details" : "Expand details")
                }
            }
            .padding(.vertical, 4)

            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(remainingProps) { prop in
                        FieldValueView(
                            value: effectiveValue(for: prop.propertyKey),
                            propertyType: prop.propertyType,
                            label: prop.propertyName,
                            showLabel: true,
                            onToggle: prop.propertyType == "boolean" ? { newVal in
                                onUpdateField(prop.propertyKey, newVal)
                            } : nil
                        )
                    }
                }
                .padding(.leading, 4)
                .padding(.bottom, 6)
            }
        }
        // Tapping anywhere on the row opens the view/edit sheet. The inline
        // toggle and the expand chevron are Buttons, so they capture their own
        // taps ahead of this gesture.
        .contentShape(Rectangle())
        .onTapGesture { onEdit() }
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Opens details to view or edit")
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if isGitHubBacked, let onSetState {
                if gitHubStateIsOpen {
                    Button {
                        onSetState("closed")
                    } label: {
                        Label("Close", systemImage: "checkmark.circle")
                    }
                    .tint(.purple)
                } else {
                    Button {
                        onSetState("open")
                    } label: {
                        Label("Reopen", systemImage: "arrow.uturn.backward.circle")
                    }
                    .tint(.green)
                }
            } else {
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            Button {
                onEdit()
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(ILColor.link)
        }
        .contextMenu {
            Button("Edit") { onEdit() }
            if isGitHubBacked, let onSetState {
                if gitHubStateIsOpen {
                    Button("Close Issue") { onSetState("closed") }
                } else {
                    Button("Reopen Issue") { onSetState("open") }
                }
            } else {
                Button("Delete", role: .destructive) { onDelete() }
            }
        }
    }
}

// MARK: - Field value renderer

struct FieldValueView: View {
    let value: JSONValue
    let propertyType: String
    let label: String
    let showLabel: Bool
    let onToggle: ((JSONValue) -> Void)?

    private var isBool: Bool { value.boolValue == true }

    var body: some View {
        if showLabel {
            LabeledContent(label) {
                fieldContent
            }
        } else {
            fieldContent
        }
    }

    @ViewBuilder
    private var fieldContent: some View {
        switch propertyType {
        case "boolean":
            Button {
                onToggle?(.bool(!isBool))
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isBool ? "checkmark.square.fill" : "square")
                        .foregroundStyle(isBool ? ILColor.primary : Color.secondary)
                    if !showLabel {
                        Text(label)
                            .foregroundStyle(.primary)
                    }
                }
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("\(label): \(isBool ? "checked" : "unchecked")")

        case "date":
            Text(formattedDate(value.displayString))
                .foregroundStyle(.primary)

        case "url":
            let raw = value.displayString
            if !raw.isEmpty, let url = URL(string: raw) {
                Link(raw, destination: url)
            } else {
                Text(raw).foregroundStyle(.primary)
            }

        case "email":
            let raw = value.displayString
            if !raw.isEmpty, let url = URL(string: "mailto:\(raw)") {
                Link(raw, destination: url)
            } else {
                Text(raw).foregroundStyle(.primary)
            }

        case "select":
            let raw = value.displayString
            Text(raw.isEmpty ? "—" : raw.capitalized)
                .font(.ilBody(13))
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.secondary.opacity(0.15)))
                .foregroundStyle(.primary)

        default:
            Text(value.displayString)
                .foregroundStyle(.primary)
        }
    }

    private func formattedDate(_ raw: String) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: raw) {
            return DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .none)
        }
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: raw) {
            return DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .none)
        }
        return raw
    }
}

// MARK: - Previews

#Preview("Lists view") {
    ListsView()
        .environmentObject(AuthState())
        .environmentObject(AppDataStore())
}

#Preview("Dynamic row — multi-column") {
    let schema = [
        ListPropertyDef(id: "1", propertyKey: "title", propertyName: "Title", propertyType: "text", displayOrder: 0, isVisible: true, isRequired: true, defaultValue: nil, helpText: nil, placeholder: nil),
        ListPropertyDef(id: "2", propertyKey: "read", propertyName: "Have Read", propertyType: "boolean", displayOrder: 1, isVisible: true, isRequired: false, defaultValue: nil, helpText: nil, placeholder: nil),
        ListPropertyDef(id: "3", propertyKey: "price", propertyName: "Price", propertyType: "number", displayOrder: 2, isVisible: true, isRequired: false, defaultValue: nil, helpText: nil, placeholder: nil),
    ]
    let item = ListItem(id: "r1", rowData: ["title": .string("Dune"), "read": .bool(true), "price": .number(14.99)], rowNumber: 1, createdAt: nil)
    return List {
        DynamicItemRow(item: item, schema: schema, pendingUpdates: [:], onUpdateField: { _, _ in }, onEdit: {}, onDelete: {})
    }
}

#Preview("Field value — boolean") {
    List {
        FieldValueView(value: .bool(true), propertyType: "boolean", label: "Completed", showLabel: false, onToggle: { _ in })
        FieldValueView(value: .bool(false), propertyType: "boolean", label: "Completed", showLabel: true, onToggle: { _ in })
        FieldValueView(value: .string("hello@example.com"), propertyType: "email", label: "Email", showLabel: true, onToggle: nil)
    }
}
