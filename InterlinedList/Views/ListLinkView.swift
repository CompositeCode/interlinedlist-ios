//
//  ListLinkView.swift
//  InterlinedList
//

import SwiftUI

/// Loader shown when a bare `/lists/<id>` permalink opens — the link the app
/// itself hands out (`ILWebURL.list(_:)`). `ListDetailView` needs a whole
/// `UserList` but the link carries only an id, so this resolves the list from
/// the lists already in the store (owned, then shared-in) and falls back to
/// `GET /api/lists/:id`, which authorizes by role. Mirrors `MessageLinkView`.
struct ListLinkView: View {
    let listId: String

    @EnvironmentObject private var authState: AuthState
    @EnvironmentObject private var store: AppDataStore
    @Environment(\.dismiss) private var dismiss
    @State private var list: UserList?
    @State private var errorMessage: String?
    @State private var hasNoAccess = false
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            Group {
                if let list {
                    ListDetailView(list: list)
                        .environmentObject(authState)
                } else if isLoading {
                    ProgressView("Loading list…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if hasNoAccess {
                    ContentUnavailableView {
                        Label("No access to this list", systemImage: "lock")
                    } description: {
                        Text("You don't have access to this list. Ask its owner to share it with you.")
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel("You don't have access to this list")
                } else {
                    ContentUnavailableView {
                        Label("Unable to open list", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(errorMessage ?? "This list could not be loaded.")
                    } actions: {
                        Button("Retry") { Task { await load() } }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        errorMessage = nil
        hasNoAccess = false
        isLoading = true
        defer { isLoading = false }
        if let known = store.userLists.first(where: { $0.id == listId })
            ?? store.watchedLists.first(where: { $0.id == listId }) {
            list = known
            return
        }
        do {
            list = try await APIClient.shared.list(id: listId)
        } catch ListAccessError.noAccess {
            hasNoAccess = true
        } catch APIError.status(401) {
            authState.handleUnauthorized()
            errorMessage = "You need to be signed in to view this list."
        } catch APIError.server(let msg) {
            errorMessage = msg
        } catch {
            errorMessage = "This list could not be loaded."
        }
    }
}

#Preview {
    ListLinkView(listId: "preview-id")
        .environmentObject(AuthState())
        .environmentObject(AppDataStore())
}
