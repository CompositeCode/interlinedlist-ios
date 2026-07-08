//
//  ListsView.swift
//  InterlinedList
//

import SwiftUI

struct ListsView: View {
    @EnvironmentObject var authState: AuthState
    @EnvironmentObject var store: AppDataStore
    @State private var showCreateList = false
    @State private var showCreateFolder = false
    @State private var createError: String?
    @State private var searchText = ""
    @State private var searchResults: [UserList] = []
    @State private var isSearching = false
    @State private var treeNodes: [ListTreeNode] = []

    private var canCreateFolders: Bool {
        authState.user?.isSubscriber == true
    }

    private func rebuildTree() -> [ListTreeNode] {
        // Folders are a subscriber-only feature. For free users we pass an empty
        // folder array so any lists that were nested under folders (e.g. from when
        // the user was a subscriber) surface at root via buildTree's orphan rule.
        let visibleFolders = canCreateFolders ? store.listFolders : []
        return ListTreeNode.buildTree(folders: visibleFolders, lists: store.userLists)
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
            }
            .sheet(isPresented: $showCreateFolder) {
                CreateListFolderView(parentId: nil) {
                    Task { await store.refreshLists() }
                }
            }
            .refreshable {
                await store.refreshLists()
            }
            .onAppear { treeNodes = rebuildTree() }
            .onChange(of: store.userLists) { _, _ in treeNodes = rebuildTree() }
            .onChange(of: store.listFolders) { _, _ in treeNodes = rebuildTree() }
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
                        onDeleteFolder: { folder in Task { await deleteFolder(folder) } },
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
            if canCreateFolders {
                Button { showCreateFolder = true } label: {
                    Label("New Folder", systemImage: "folder.badge.plus")
                }
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
                    ListNameWithVisibility(name: list.name, isPublic: list.isPublic)
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

    private func deleteFolder(_ folder: ListFolder) async {
        do {
            try await APIClient.shared.deleteListFolder(id: folder.id)
            store.removeListFolder(id: folder.id)
        } catch APIError.status(401) {
            authState.handleUnauthorized()
        } catch {
            await store.refreshLists()
        }
    }
}

// MARK: - Create list folder sheet

private struct CreateListFolderView: View {
    let parentId: String?
    let onSave: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Folder Name") {
                    TextField("Name", text: $name)
                }
                if let error = errorMessage {
                    Section {
                        Text(error).foregroundStyle(.red).font(.ilMono())
                    }
                }
            }
            .navigationTitle("New Folder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Create") { Task { await save() } }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
                }
            }
        }
    }

    private func save() async {
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil
        do {
            _ = try await APIClient.shared.createListFolder(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                parentId: parentId
            )
            onSave()
            dismiss()
        } catch APIError.server(let msg) {
            errorMessage = msg
        } catch {
            // 403 falls through here — the New Folder button is hidden for
            // non-subscribers, so this catch should only trigger on transient
            // errors. Per the iOS-free-app direction, no subscription copy is
            // ever surfaced.
            errorMessage = "Failed to create folder."
        }
    }
}

// MARK: - Rename list sheet

private struct RenameListView: View {
    let list: UserList
    let onSave: (UserList) -> Void

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
    let onDeleteFolder: (ListFolder) -> Void
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
                    ListTreeNodeRow(node: child, onDeleteList: onDeleteList, onDeleteFolder: onDeleteFolder, onUpdateList: onUpdateList)
                }
            } label: {
                NavigationLink(value: list) {
                    ListNameWithVisibility(name: node.name, isPublic: list.isPublic)
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
        } else if let children = node.children {
            DisclosureGroup(isExpanded: $isExpanded) {
                ForEach(children) { child in
                    ListTreeNodeRow(node: child, onDeleteList: onDeleteList, onDeleteFolder: onDeleteFolder, onUpdateList: onUpdateList)
                }
            } label: {
                Label(node.name, systemImage: "folder.fill")
                    .foregroundStyle(.primary)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive) {
                    if let folder = folderFromNode(node) {
                        onDeleteFolder(folder)
                    }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        } else if let list = node.list {
            NavigationLink(value: list) {
                ListNameWithVisibility(name: node.name, isPublic: list.isPublic)
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

    private func folderFromNode(_ node: ListTreeNode) -> ListFolder? {
        guard node.list == nil, node.children != nil else { return nil }
        return ListFolder(id: node.id, name: node.name, parentId: nil, createdAt: nil)
    }
}

private struct ListNameWithVisibility: View {
    let name: String
    let isPublic: Bool?

    var body: some View {
        HStack(spacing: 6) {
            Text(name)
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
    @State private var showAddItem = false
    @State private var editingItem: ListItem? = nil
    @State private var deletingItem: ListItem? = nil
    @State private var showDeleteConfirm = false
    @State private var showWatchers = false

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
                    if items.isEmpty && !isLoading {
                        ContentUnavailableView {
                            Label("Empty List", systemImage: "list.bullet")
                        } description: {
                            Text("This list has no items yet.")
                        }
                    } else {
                        ForEach(items) { item in
                            DynamicItemRow(
                                item: item,
                                schema: schema,
                                pendingUpdates: pendingUpdates[item.id] ?? [:],
                                onUpdateField: { key, value in
                                    Task { await updateField(item: item, key: key, value: value) }
                                },
                                onEdit: {
                                    editingItem = item
                                },
                                onDelete: {
                                    deletingItem = item
                                    showDeleteConfirm = true
                                }
                            )
                        }
                    }
                    Section {
                        Button {
                            showAddItem = true
                        } label: {
                            Label("Add Item", systemImage: "plus")
                        }
                        .disabled(schema.isEmpty)
                        .accessibilityLabel("Add item to list")
                    }
                    Section {
                        if connections.isEmpty {
                            Text("No connections yet")
                                .foregroundStyle(.secondary)
                                .font(.ilBody(15))
                        } else {
                            ForEach(connections) { conn in
                                let otherListId = conn.sourceListId == list.id ? conn.targetListId : conn.sourceListId
                                let otherList = allLists.first { $0.id == otherListId }
                                HStack {
                                    Image(systemName: "link")
                                        .foregroundStyle(.secondary)
                                    Text(otherList?.name ?? otherListId)
                                }
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
                            Text("Connections")
                            Spacer()
                            Button {
                                showAddConnection = true
                            } label: {
                                Image(systemName: "plus")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Add connection")
                        }
                    }
                }
            }
        }
        .navigationTitle(list.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showWatchers = true
                } label: {
                    Image(systemName: "person.2")
                }
                .accessibilityLabel("Manage watchers")
            }
        }
        .task {
            await loadData()
        }
        .refreshable {
            await loadData()
        }
        .sheet(isPresented: $showWatchers) {
            WatchersListView(listId: list.id)
                .environmentObject(authState)
        }
        .sheet(isPresented: $showAddConnection) {
            NavigationStack {
                List {
                    ForEach(allLists.filter { $0.id != list.id }) { candidate in
                        Button(candidate.name) {
                            Task {
                                if let conn = try? await APIClient.shared.createListConnection(
                                    sourceListId: list.id,
                                    targetListId: candidate.id
                                ) {
                                    connections.append(conn)
                                }
                                showAddConnection = false
                            }
                        }
                    }
                }
                .navigationTitle("Connect to List")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showAddConnection = false }
                    }
                }
            }
        }
        .sheet(isPresented: $showAddItem) {
            ListItemFormView(schema: schema, existingItem: nil) { rowData in
                Task { await addItem(rowData: rowData) }
            }
        }
        .sheet(item: $editingItem) { item in
            ListItemFormView(schema: schema, existingItem: item) { rowData in
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
            async let allListsTask = APIClient.shared.listsAndFolders()
            let (fetchedSchema, fetchedItems) = try await (schemaTask, itemsTask)
            schema = fetchedSchema
            items = fetchedItems
            pendingUpdates = [:]
            let listId = list.id
            connections = (try? await connectionsTask)?
                .filter { $0.sourceListId == listId || $0.targetListId == listId } ?? []
            allLists = (try? await allListsTask)?.lists ?? []
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
    let onUpdateField: (String, JSONValue) -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    @State private var isExpanded = false

    private var visibleProps: [ListPropertyDef] {
        schema.filter { $0.isVisible }
    }

    private var primaryProp: ListPropertyDef? {
        visibleProps.first
    }

    private var remainingProps: [ListPropertyDef] {
        visibleProps.count > 1 ? Array(visibleProps.dropFirst()) : []
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
                    Text(item.rowData.sorted(by: { $0.key < $1.key }).first?.value.displayString ?? "—")
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
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
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
            Button("Delete", role: .destructive) { onDelete() }
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
