//
//  BlockedUsersView.swift
//  InterlinedList
//

import SwiftUI

struct BlockedUsersView: View {
    @EnvironmentObject private var authState: AuthState
    @State private var blockedUsers: [BlockedUser] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var actionError: String?

    var body: some View {
        Group {
            if isLoading && blockedUsers.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error, blockedUsers.isEmpty {
                ContentUnavailableView {
                    Label("Unable to load", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Retry") { Task { await load() } }
                }
            } else if blockedUsers.isEmpty {
                ContentUnavailableView(
                    "No blocked users",
                    systemImage: "person.slash",
                    description: Text("Users you block will appear here.")
                )
            } else {
                List {
                    if let actionError {
                        Section {
                            Text(actionError).font(.ilMono()).foregroundStyle(.red)
                        }
                    }
                    ForEach(blockedUsers) { user in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("@\(user.username)")
                                    .font(.ilBody(15))
                                    .fontWeight(.medium)
                                if let displayName = user.displayName, !displayName.isEmpty {
                                    Text(displayName)
                                        .font(.ilBody())
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Button("Unblock") {
                                Task { await unblock(user) }
                            }
                            .buttonStyle(.bordered)
                            .font(.ilMono())
                            .accessibilityLabel("Unblock @\(user.username)")
                        }
                    }
                }
            }
        }
        .navigationTitle("Blocked Users")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let response = try await APIClient.shared.blockedUsers()
            blockedUsers = response.blockedUsers
        } catch APIError.status(401) {
            authState.handleUnauthorized()
        } catch {
            self.error = "Could not load blocked users."
        }
    }

    private func unblock(_ user: BlockedUser) async {
        actionError = nil
        do {
            try await APIClient.shared.unblockUser(id: user.id)
            blockedUsers.removeAll { $0.id == user.id }
        } catch APIError.status(401) {
            authState.handleUnauthorized()
        } catch {
            actionError = "Could not unblock @\(user.username)."
        }
    }
}

#Preview {
    NavigationStack {
        BlockedUsersView()
            .environmentObject(AuthState())
    }
}
