//
//  MessageLinkView.swift
//  InterlinedList
//

import SwiftUI

/// Loader shown when a `interlinedlist://message/<id>` (or web permalink) deep link
/// opens. `MessageDetailView` needs a full `Message`, but a deep link only carries an
/// id, so this fetches the message first and presents loading / error / loaded states.
struct MessageLinkView: View {
    let messageId: String

    @EnvironmentObject private var authState: AuthState
    @EnvironmentObject private var store: AppDataStore
    @Environment(\.dismiss) private var dismiss
    @State private var message: Message?
    @State private var errorMessage: String?
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            Group {
                if let message {
                    MessageDetailView(message: message, currentUserId: authState.user?.id)
                        .environmentObject(authState)
                        .environmentObject(store)
                } else if isLoading {
                    ProgressView("Loading post…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ContentUnavailableView {
                        Label("Unable to open post", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(errorMessage ?? "This post could not be loaded.")
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
        isLoading = true
        defer { isLoading = false }
        do {
            message = try await APIClient.shared.message(id: messageId)
        } catch APIError.status(401) {
            authState.handleUnauthorized()
            errorMessage = "You need to be signed in to view this post."
        } catch APIError.server(let msg) {
            errorMessage = msg
        } catch {
            errorMessage = "This post could not be loaded."
        }
    }
}

#Preview {
    MessageLinkView(messageId: "preview-id")
        .environmentObject(AuthState())
        .environmentObject(AppDataStore())
}
