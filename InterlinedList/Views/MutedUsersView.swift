//
//  MutedUsersView.swift
//  InterlinedList
//

import SwiftUI

struct MutedUsersView: View {
    @EnvironmentObject private var authState: AuthState
    @State private var mutedUsers: [MutedUser] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var actionError: String?

    var body: some View {
        Group {
            if isLoading && mutedUsers.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error, mutedUsers.isEmpty {
                ContentUnavailableView {
                    Label("Unable to load", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Retry") { Task { await load() } }
                }
            } else if mutedUsers.isEmpty {
                ContentUnavailableView(
                    "No muted users",
                    systemImage: "speaker.slash",
                    description: Text("Users you mute will appear here.")
                )
            } else {
                List {
                    if let actionError {
                        Section {
                            Text(actionError).font(.ilMono()).foregroundStyle(.red)
                        }
                    }
                    ForEach(mutedUsers) { user in
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
                            Button("Unmute") {
                                Task { await unmute(user) }
                            }
                            .buttonStyle(.bordered)
                            .font(.ilMono())
                            .accessibilityLabel("Unmute @\(user.username)")
                        }
                    }
                }
            }
        }
        .navigationTitle("Muted Users")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let response = try await APIClient.shared.mutedUsers()
            mutedUsers = response.mutedUsers
        } catch APIError.status(401) {
            authState.handleUnauthorized()
        } catch {
            self.error = "Could not load muted users."
        }
    }

    private func unmute(_ user: MutedUser) async {
        actionError = nil
        do {
            try await APIClient.shared.unmuteUser(id: user.id)
            mutedUsers.removeAll { $0.id == user.id }
        } catch APIError.status(401) {
            authState.handleUnauthorized()
        } catch {
            actionError = "Could not unmute @\(user.username)."
        }
    }
}

#Preview {
    NavigationStack {
        MutedUsersView()
            .environmentObject(AuthState())
    }
}
