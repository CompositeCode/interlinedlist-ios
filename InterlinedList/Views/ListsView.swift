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
                            ListTreeNodeRow(node: node)
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
            .task {
                await loadLists()
            }
            .refreshable {
                await loadLists()
            }
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
    @State private var isExpanded = true

    var body: some View {
        if let children = node.children {
            DisclosureGroup(isExpanded: $isExpanded) {
                ForEach(children) { child in
                    ListTreeNodeRow(node: child)
                }
            } label: {
                Label(node.name, systemImage: "folder.fill")
                    .foregroundStyle(.primary)
            }
        } else if let list = node.list {
            NavigationLink(value: list) {
                Label(node.name, systemImage: "list.bullet")
            }
        }
    }
}

// MARK: - List detail

struct ListDetailView: View {
    let list: UserList
    @EnvironmentObject var authState: AuthState
    @State private var items: [ListItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage {
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
            } else if items.isEmpty {
                ContentUnavailableView {
                    Label("Empty List", systemImage: "list.bullet")
                } description: {
                    Text("This list has no items yet.")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(items) { item in
                    ListItemRow(item: item)
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

    private func loadItems() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            items = try await APIClient.shared.listItems(listId: list.id)
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

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.checked == true ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(item.checked == true ? Color.green : Color.secondary)
            Text(item.content)
                .strikethrough(item.checked == true)
                .foregroundStyle(item.checked == true ? Color.secondary : Color.primary)
        }
        .padding(.vertical, 2)
    }
}
