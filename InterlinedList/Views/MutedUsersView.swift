//
//  MutedUsersView.swift
//  InterlinedList
//

import SwiftUI

struct MutedUsersView: View {
    @EnvironmentObject private var authState: AuthState
    @ObservedObject private var muteStore = MuteStore.shared
    @State private var isLoading = true
    @State private var error: String?
    @State private var actionError: String?

    private var mutedUsers: [MutedUser] { muteStore.mutedUsers }

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
            try await muteStore.refresh()
        } catch APIError.status(401) {
            authState.handleUnauthorized()
        } catch {
            self.error = "Could not load muted users."
        }
    }

    private func unmute(_ user: MutedUser) async {
        actionError = nil
        do {
            try await muteStore.unmute(userId: user.id)
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
