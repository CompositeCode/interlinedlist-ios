//
//  LinkedIdentitiesView.swift
//  InterlinedList
//

import SwiftUI

/// Lists the OAuth providers linked to the signed-in account, reports how healthy
/// each connection looks, and lets the user disconnect (`DELETE /api/user/identities`)
/// or reconnect a stale one. Reachable only for subscribers (gated by the caller in
/// `MainTabView`).
struct LinkedIdentitiesView: View {
    @EnvironmentObject var authState: AuthState

    /// In-app linking of a *new* provider is disabled: the backend `?link=true`
    /// callback authenticates via the web session cookie (`getCurrentUser()`), not
    /// the Bearer token, so a native client can't link a new provider through it.
    /// Flip to `true` once the backend exposes a Bearer-authenticated link endpoint.
    /// (Backend auth contract — Open Dependency #2.)
    private let linkingEnabled = false

    @State private var identities: [APIClient.LinkedIdentity] = []
    @State private var statusSnapshot: IdentityStatusSnapshot?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var pendingUnlink: APIClient.LinkedIdentity?
    @State private var linkInFlight = false
    @State private var showMastodonPrompt = false
    @State private var mastodonInstance = ""
    /// Set when the Mastodon prompt is repairing an existing row rather than
    /// linking a fresh one, so the reconnect follow-up can re-check that row.
    @State private var reconnectingIdentity: APIClient.LinkedIdentity?

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
            } footer: {
                if !isLoading && !identities.isEmpty {
                    Text("A connection shown as unknown couldn't be checked — it hasn't been disconnected.")
                        .font(.ilMono(12))
                }
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
                runLink(provider: .mastodon, instance: mastodonInstance, reconnecting: reconnectingIdentity)
                reconnectingIdentity = nil
            }
            Button("Cancel", role: .cancel) { reconnectingIdentity = nil }
        } message: {
            Text("Enter your Mastodon server hostname.")
        }
    }

    @ViewBuilder
    private func identityRow(_ identity: APIClient.LinkedIdentity) -> some View {
        let health = statusSnapshot?.health(for: identity)
        HStack(spacing: 12) {
            Image(systemName: OAuthProvider(rawValue: identity.providerType)?.systemImageName ?? "link")
                .frame(width: 24)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(displayName(for: identity.provider))
                    .font(.ilBody())
                if let username = identity.providerUsername, !username.isEmpty {
                    Text("@\(username)")
                        .font(.ilMono())
                        .foregroundStyle(.secondary)
                }
                healthLabel(health, for: identity)
                if health?.isStale == true {
                    Button("Reconnect") {
                        startReconnect(identity)
                    }
                    .buttonStyle(.bordered)
                    .font(.ilBody(14))
                    .disabled(linkInFlight)
                    .accessibilityLabel("Reconnect \(displayName(for: identity.provider))")
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

    @ViewBuilder
    private func healthLabel(_ health: IdentityHealth?, for identity: APIClient.LinkedIdentity) -> some View {
        let name = displayName(for: identity.provider)
        switch health {
        case nil:
            Text("Checking…")
                .font(.ilMono(12))
                .foregroundStyle(.secondary)
                .accessibilityLabel("Checking \(name) connection")
        case .connected:
            Label("Connected", systemImage: "checkmark.circle.fill")
                .font(.ilMono(12))
                .foregroundStyle(.green)
                .accessibilityLabel("\(name) connected")
        case .needsReconnect(let reason):
            VStack(alignment: .leading, spacing: 2) {
                Label("Needs reconnect", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(reason)
                    .foregroundStyle(.secondary)
            }
            .font(.ilMono(12))
            .accessibilityLabel("\(name) needs reconnect. \(reason)")
        case .unknown(let reason):
            VStack(alignment: .leading, spacing: 2) {
                Label("Status unknown", systemImage: "questionmark.circle")
                    .foregroundStyle(.secondary)
                Text(reason)
                    .foregroundStyle(.secondary)
            }
            .font(.ilMono(12))
            .accessibilityLabel("\(name) status unknown. \(reason)")
        }
    }

    private func displayName(for provider: String) -> String {
        OAuthProvider(rawValue: String(provider.prefix(while: { $0 != ":" })))?.displayName ?? provider.capitalized
    }

    private func load() async {
        errorMessage = nil
        isLoading = true
        do {
            identities = try await APIClient.shared.linkedIdentities()
            isLoading = false
        } catch APIError.status(401) {
            isLoading = false
            authState.handleUnauthorized()
            errorMessage = "Couldn't load connected accounts."
            return
        } catch APIError.server(let message) {
            isLoading = false
            errorMessage = message
            return
        } catch {
            isLoading = false
            errorMessage = "Couldn't load connected accounts."
            return
        }
        await loadStatuses()
    }

    /// All five status routes at once. Mastodon needs one call per linked instance,
    /// which is why the instance list has to come from `identities` first.
    private func loadStatuses() async {
        let instances = Set(identities.compactMap { identity -> String? in
            identity.providerType == OAuthProvider.mastodon.rawValue ? identity.providerInstance : nil
        })

        async let linkedin = Self.statusOutcome { try await APIClient.shared.linkedinStatus().configured }
        async let twitter = Self.statusOutcome { try await APIClient.shared.twitterStatus().configured }
        async let bluesky = Self.statusOutcome { try await APIClient.shared.blueskyStatus().configured }
        async let github = Self.statusOutcome { try await APIClient.shared.githubStatus().configured }
        async let mastodon = Self.mastodonOutcomes(instances: instances)

        let snapshot = IdentityStatusSnapshot(
            linkedin: await linkedin,
            twitter: await twitter,
            bluesky: await bluesky,
            github: await github,
            mastodon: await mastodon
        )
        statusSnapshot = snapshot
        // A status-route 401 proves nothing about the session on its own, so it goes
        // through re-validation rather than a logout (CLAUDE.md).
        if snapshot.sawUnauthorized {
            authState.handleUnauthorized()
        }
    }

    private static func mastodonOutcomes(instances: Set<String>) async -> [String: ProviderStatusOutcome] {
        await withTaskGroup(of: (String, ProviderStatusOutcome).self) { group in
            for instance in instances {
                group.addTask {
                    let outcome = await statusOutcome {
                        try await APIClient.shared.mastodonStatus(instance: instance).configured
                    }
                    return (instance, outcome)
                }
            }
            return await group.reduce(into: [:]) { $0[$1.0] = $1.1 }
        }
    }

    /// Runs one status call, turning any failure into `.failed` so a dead check can
    /// never downgrade a healthy identity.
    private static func statusOutcome(_ call: @Sendable () async throws -> Bool) async -> ProviderStatusOutcome {
        do {
            return try await call() ? .configured : .notConfigured
        } catch APIError.status(401) {
            return .failed(unauthorized: true)
        } catch {
            return .failed(unauthorized: false)
        }
    }

    private func unlink(_ identity: APIClient.LinkedIdentity) async {
        errorMessage = nil
        pendingUnlink = nil
        do {
            try await APIClient.shared.unlinkIdentity(provider: identity.provider, providerId: identity.id)
            await load()
        } catch APIError.status(401) {
            authState.handleUnauthorized()
            errorMessage = "Couldn't disconnect \(displayName(for: identity.provider))."
        } catch APIError.server(let message) {
            errorMessage = message
        } catch {
            errorMessage = "Couldn't disconnect \(displayName(for: identity.provider))."
        }
    }

    private func startLink(provider: OAuthProvider) {
        if provider == .mastodon {
            mastodonInstance = ""
            reconnectingIdentity = nil
            showMastodonPrompt = true
            return
        }
        runLink(provider: provider, instance: nil, reconnecting: nil)
    }

    private func startReconnect(_ identity: APIClient.LinkedIdentity) {
        guard let provider = OAuthProvider(rawValue: identity.providerType) else { return }
        if provider == .mastodon {
            mastodonInstance = identity.providerInstance ?? ""
            reconnectingIdentity = identity
            showMastodonPrompt = true
            return
        }
        runLink(provider: provider, instance: nil, reconnecting: identity)
    }

    private func runLink(provider: OAuthProvider, instance: String?, reconnecting: APIClient.LinkedIdentity?) {
        Task {
            errorMessage = nil
            linkInFlight = true
            defer { linkInFlight = false }
            do {
                _ = try await OAuthCoordinator.shared.authenticate(provider: provider, instance: instance, link: true)
                await load()
            } catch OAuthError.cancelled {
                // The `?link=true` callback finishes on a *web* redirect, not the
                // custom-scheme token handoff, so a link that the server actually
                // completed still surfaces here as a cancellation. Reload before
                // believing it failed.
                await load()
            } catch OAuthError.providerError(let message) {
                errorMessage = message
            } catch {
                errorMessage = "Couldn't link \(provider.displayName). Please try again."
            }
            if let reconnecting, stillStale(reconnecting) {
                errorMessage = "Couldn't confirm the \(provider.displayName) reconnect. Finish connecting at interlinedlist.com."
            }
        }
    }

    private func stillStale(_ identity: APIClient.LinkedIdentity) -> Bool {
        guard let snapshot = statusSnapshot,
              let current = identities.first(where: { $0.id == identity.id }) else { return false }
        return snapshot.health(for: current).isStale
    }
}

#Preview {
    NavigationStack {
        LinkedIdentitiesView()
            .environmentObject(AuthState())
    }
}
