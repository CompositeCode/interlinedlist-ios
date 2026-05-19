//
//  ListsView.swift
//  InterlinedList
//

import SwiftUI

struct ListsView: View {
    @EnvironmentObject var authState: AuthState
    @State private var treeNodes: [ListTreeNode] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showCreateList = false
    @State private var createError: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading lists…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = errorMessage, treeNodes.isEmpty {
                    ContentUnavailableView {
                        Label("Unable to load", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Retry") {
                            Task { await loadLists() }
                        }
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
                            ListTreeNodeRow(node: node, onDeleteList: { list in
                                Task { await deleteList(list) }
                            })
                        }
                    }
                    .listStyle(.sidebar)
                }
            }
            .navigationTitle("Lists")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: UserList.self) { list in
                ListDetailView(list: list)
                    .environmentObject(authState)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showCreateList = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showCreateList) {
                CreateListView { _ in
                    Task { await loadLists() }
                }
            }
            .task {
                await loadLists()
            }
            .refreshable {
                await loadLists()
            }
        }
    }

    private func deleteList(_ list: UserList) async {
        do {
            try await APIClient.shared.deleteList(id: list.id)
            await loadLists()
        } catch APIError.status(401) {
            authState.handleUnauthorized()
        } catch {
            // Reload anyway to reflect server state
            await loadLists()
        }
    }

    private func loadLists() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let (folders, lists) = try await APIClient.shared.listsAndFolders()
            treeNodes = ListTreeNode.buildTree(folders: folders, lists: lists)
        } catch APIError.status(401) {
            authState.handleUnauthorized()
        } catch APIError.server(let msg) {
            errorMessage = msg
        } catch {
            errorMessage = "Connection failed. Please try again."
        }
    }
}

// MARK: - Tree row

struct ListTreeNodeRow: View {
    let node: ListTreeNode
    let onDeleteList: (UserList) -> Void
    @State private var isExpanded = true

    var body: some View {
        if let children = node.children {
            DisclosureGroup(isExpanded: $isExpanded) {
                ForEach(children) { child in
                    ListTreeNodeRow(node: child, onDeleteList: onDeleteList)
                }
            } label: {
                Label(node.name, systemImage: "folder.fill")
                    .foregroundStyle(.primary)
            }
        } else if let list = node.list {
            NavigationLink(value: list) {
                Label(node.name, systemImage: "list.bullet")
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive) {
                    onDeleteList(list)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }
}

// MARK: - List detail

struct ListDetailView: View {
    let list: UserList
    @EnvironmentObject var authState: AuthState
    @State private var items: [ListItem] = []
    @State private var checkStates: [String: Bool] = [:]
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var newItemText = ""
    @State private var addItemError: String?
    @State private var isAdding = false

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
                        Task { await loadItems() }
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
                            ListItemRow(
                                item: item,
                                isChecked: checkStates[item.id] ?? (item.checked ?? false),
                                onToggle: { Task { await toggleItem(item) } }
                            )
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                let item = items[index]
                                Task { await deleteItem(item) }
                            }
                        }
                    }
                    Section {
                        HStack {
                            TextField("Add item…", text: $newItemText)
                            Button {
                                Task { await addItem() }
                            } label: {
                                if isAdding {
                                    ProgressView()
                                        .frame(width: 20, height: 20)
                                } else {
                                    Text("Add")
                                }
                            }
                            .buttonStyle(.borderless)
                            .disabled(isAdding || newItemText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        if let error = addItemError {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
        }
        .navigationTitle(list.name)
        .navigationBarTitleDisplayMode(.large)
        .task {
            await loadItems()
        }
        .refreshable {
            await loadItems()
        }
    }

    private func addItem() async {
        addItemError = nil
        isAdding = true
        defer { isAdding = false }
        let text = newItemText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        do {
            let item = try await APIClient.shared.addListItem(listId: list.id, content: text)
            items.append(item)
            newItemText = ""
        } catch APIError.status(401) {
            authState.handleUnauthorized()
        } catch APIError.server(let msg) {
            addItemError = msg
        } catch {
            addItemError = "Failed to add item."
        }
    }

    private func deleteItem(_ item: ListItem) async {
        do {
            try await APIClient.shared.deleteListItem(listId: list.id, itemId: item.id)
            items.removeAll { $0.id == item.id }
        } catch APIError.status(401) {
            authState.handleUnauthorized()
        } catch {
            await loadItems()
        }
    }

    private func toggleItem(_ item: ListItem) async {
        let current = checkStates[item.id] ?? (item.checked ?? false)
        let next = !current
        checkStates[item.id] = next
        do {
            let updated = try await APIClient.shared.toggleListItem(listId: list.id, itemId: item.id, checked: next)
            checkStates[item.id] = updated.checked ?? next
        } catch APIError.status(401) {
            authState.handleUnauthorized()
            checkStates[item.id] = current
        } catch {
            checkStates[item.id] = current
        }
    }

    private func loadItems() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            items = try await APIClient.shared.listItems(listId: list.id)
            for item in items {
                checkStates[item.id] = item.checked ?? false
            }
        } catch APIError.status(401) {
            authState.handleUnauthorized()
        } catch APIError.server(let msg) {
            errorMessage = msg
        } catch {
            errorMessage = "Failed to load items."
        }
    }
}

// MARK: - List item row

struct ListItemRow: View {
    let item: ListItem
    let isChecked: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button { onToggle() } label: {
                Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isChecked ? Color.green : Color.secondary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(isChecked ? "Uncheck item" : "Check item")
            Text(item.content)
                .strikethrough(isChecked)
                .foregroundStyle(isChecked ? Color.secondary : Color.primary)
        }
        .padding(.vertical, 2)
    }
}
