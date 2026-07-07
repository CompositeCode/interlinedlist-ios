//
//  LinkedIdentitiesView.swift
//  InterlinedList
//

import SwiftUI

/// Lists the OAuth providers linked to the signed-in account and lets the user disconnect
/// them (`DELETE /api/user/identities`). In-app *linking* of a new provider is gated off
/// (see `linkingEnabled`). Reachable only for subscribers (gated by the caller in `MainTabView`).
struct LinkedIdentitiesView: View {
    @EnvironmentObject var authState: AuthState

    /// In-app provider linking is disabled: the backend `?link=true` callback
    /// authenticates via the web session cookie (`getCurrentUser()`), not the
    /// Bearer token, so a native (Bearer-only) client can't link a new provider
    /// through it. Flip to `true` once the backend exposes a Bearer-authenticated
    /// link endpoint. (Backend auth contract — Open Dependency #2.)
    private let linkingEnabled = false

    @State private var identities: [APIClient.LinkedIdentity] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var pendingUnlink: APIClient.LinkedIdentity?
    @State private var linkInFlight = false
    @State private var showMastodonPrompt = false
    @State private var mastodonInstance = ""

    var body: some View {
        List {
            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.ilMono())
                        .foregroundStyle(.red)
                }
            }

            Section {
                if isLoading {
                    HStack { ProgressView(); Text("Loading…").foregroundStyle(.secondary) }
                } else if identities.isEmpty {
                    Text("No connected accounts yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(identities) { identity in
                        identityRow(identity)
                    }
                }
            } header: {
                Text("Connected accounts")
            }

            if linkingEnabled {
                Section {
                    Menu {
                        ForEach(OAuthProvider.allCases.filter(\.supportsNativeAuth), id: \.rawValue) { provider in
                            Button {
                                startLink(provider: provider)
                            } label: {
                                Label(provider.displayName, systemImage: provider.systemImageName)
                            }
                        }
                    } label: {
                        HStack {
                            Label("Link another provider", systemImage: "plus.circle")
                            Spacer()
                            if linkInFlight { ProgressView() }
                        }
                    }
                    .disabled(linkInFlight)
                }
            } else {
                Section {
                    Text("To connect another account, sign in at interlinedlist.com. In-app linking will return once it's supported for app sign-ins.")
                        .font(.ilMono())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Linked accounts")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .alert("Disconnect account?", isPresented: Binding(
            get: { pendingUnlink != nil },
            set: { if !$0 { pendingUnlink = nil } }
        ), presenting: pendingUnlink) { identity in
            Button("Disconnect", role: .destructive) {
                Task { await unlink(identity) }
            }
            Button("Cancel", role: .cancel) { pendingUnlink = nil }
        } message: { identity in
            Text("You'll no longer be able to sign in with \(displayName(for: identity.provider)).")
        }
        .alert("Mastodon instance", isPresented: $showMastodonPrompt) {
            TextField("mastodon.social", text: $mastodonInstance)
                .textInputAutocapitalization(.never)
            Button("Continue") {
                runLink(provider: .mastodon, instance: mastodonInstance)
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Enter your Mastodon server hostname.")
        }
    }

    @ViewBuilder
    private func identityRow(_ identity: APIClient.LinkedIdentity) -> some View {
        HStack(spacing: 12) {
            Image(systemName: OAuthProvider(rawValue: identity.providerType)?.systemImageName ?? "link")
                .frame(width: 24)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(displayName(for: identity.provider))
                    .font(.ilBody())
                if let username = identity.providerUsername, !username.isEmpty {
                    Text("@\(username)")
                        .font(.ilMono())
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("Disconnect", role: .destructive) {
                pendingUnlink = identity
            }
            .buttonStyle(.borderless)
            .font(.ilBody(15))
            .accessibilityLabel("Disconnect \(displayName(for: identity.provider))")
        }
    }

    private func displayName(for provider: String) -> String {
        OAuthProvider(rawValue: String(provider.prefix(while: { $0 != ":" })))?.displayName ?? provider.capitalized
    }

    private func load() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            identities = try await APIClient.shared.linkedIdentities()
        } catch APIError.server(let message) {
            errorMessage = message
        } catch {
            errorMessage = "Couldn't load connected accounts."
        }
    }

    private func unlink(_ identity: APIClient.LinkedIdentity) async {
        errorMessage = nil
        pendingUnlink = nil
        do {
            try await APIClient.shared.unlinkIdentity(provider: identity.provider, providerId: identity.id)
            await load()
        } catch APIError.server(let message) {
            errorMessage = message
        } catch {
            errorMessage = "Couldn't disconnect \(displayName(for: identity.provider))."
        }
    }

    private func startLink(provider: OAuthProvider) {
        if provider == .mastodon {
            mastodonInstance = ""
            showMastodonPrompt = true
            return
        }
        runLink(provider: provider, instance: nil)
    }

    private func runLink(provider: OAuthProvider, instance: String?) {
        Task {
            errorMessage = nil
            linkInFlight = true
            defer { linkInFlight = false }
            do {
                _ = try await OAuthCoordinator.shared.authenticate(provider: provider, instance: instance, link: true)
                await load()
            } catch OAuthError.cancelled {
                // User backed out — nothing to surface.
            } catch OAuthError.providerError(let message) {
                errorMessage = message
            } catch {
                errorMessage = "Couldn't link \(provider.displayName). Please try again."
            }
        }
    }
}

#Preview {
    NavigationStack {
        LinkedIdentitiesView()
            .environmentObject(AuthState())
    }
}
