//
//  RegisterView.swift
//  InterlinedList
//

import SwiftUI

struct RegisterView: View {
    @EnvironmentObject var authState: AuthState
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var username = ""
    @State private var displayName = ""
    @State private var password = ""
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var showMastodonPrompt = false
    @State private var mastodonInstance = ""
    @State private var oauthInFlight = false
    @State private var linkedinVisible = false
    @State private var twitterVisible = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .autocapitalization(.none)
                        .keyboardType(.emailAddress)
                    TextField("Username", text: $username)
                        .textContentType(.username)
                        .autocapitalization(.none)
                    TextField("Display name (optional)", text: $displayName)
                        .textContentType(.name)
                    SecureField("Password", text: $password)
                        .textContentType(.newPassword)
                } header: {
                    Text("Create account")
                } footer: {
                    Text("Password must be at least 8 characters.")
                }

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }

                Section {
                    Button {
                        Task { await register() }
                    } label: {
                        HStack {
                            if isLoading {
                                ProgressView()
                                    .frame(width: 20, height: 20)
                            }
                            Text("Create account")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(isLoading || email.isEmpty || username.isEmpty || password.count < 8)
                }

                Section("Or sign up with") {
                    ForEach(visibleProviders, id: \.rawValue) { provider in
                        OAuthSignInButton(provider: provider, inFlight: oauthInFlight) {
                            handleOAuthTap(provider: provider)
                        }
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Sign up")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .alert("Mastodon instance",
                   isPresented: $showMastodonPrompt) {
                TextField("mastodon.social", text: $mastodonInstance)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                Button("Continue") {
                    Task { await runOAuth(provider: .mastodon, instance: mastodonInstance) }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Enter your Mastodon server hostname.")
            }
        }
        .task { await refreshOAuthVisibility() }
        .onAppear { errorMessage = nil }
    }

    private var visibleProviders: [OAuthProvider] {
        OAuthProvider.allCases.filter {
            guard $0.supportsNativeAuth else { return false }
            switch $0 {
            case .linkedin: return linkedinVisible
            case .twitter: return twitterVisible
            default: return true
            }
        }
    }

    private func refreshOAuthVisibility() async {
        async let li = APIClient.shared.linkedinStatus()
        async let tw = APIClient.shared.twitterStatus()
        if let liStatus = try? await li { linkedinVisible = liStatus.configured } else { linkedinVisible = false }
        if let twStatus = try? await tw { twitterVisible = twStatus.configured } else { twitterVisible = false }
    }

    private func handleOAuthTap(provider: OAuthProvider) {
        if provider == .mastodon {
            mastodonInstance = ""
            showMastodonPrompt = true
            return
        }
        Task { await runOAuth(provider: provider, instance: nil) }
    }

    private func runOAuth(provider: OAuthProvider, instance: String?) async {
        errorMessage = nil
        oauthInFlight = true
        defer { oauthInFlight = false }
        do {
            let token = try await OAuthCoordinator.shared.authenticate(
                provider: provider,
                instance: instance,
                link: false
            )
            try await authState.completeOAuthLogin(token: token)
            dismiss()
        } catch OAuthError.cancelled {
            // No surfaced error.
        } catch OAuthError.providerError(let message) {
            errorMessage = message
        } catch {
            errorMessage = "Sign-up with \(provider.displayName) failed. Please try again."
        }
    }

    private func register() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            try await authState.register(
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                username: username.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password,
                displayName: name.isEmpty ? nil : name
            )
            dismiss()
        } catch APIError.server(let message) {
            errorMessage = message
        } catch APIError.status(409) {
            errorMessage = "A user with this email or username already exists."
        } catch {
            errorMessage = "Connection failed. Please try again."
        }
    }
}
