//
//  LoginView.swift
//  InterlinedList
//

import SwiftUI

struct LoginView: View {
    @EnvironmentObject var authState: AuthState
    @State private var email = ""
    @State private var password = ""
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var showRegister = false
    @State private var showForgotPassword = false
    @State private var showMastodonPrompt = false
    @State private var mastodonInstance = ""
    @State private var oauthInFlight = false
    @State private var linkedinVisible = false
    @State private var twitterVisible = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Image("Logo")
                        .resizable()
                        .frame(width: 80, height: 80)
                        .clipped()
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 20, leading: 0, bottom: 10, trailing: 0))
                }
                Section {
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .autocapitalization(.none)
                        .keyboardType(.emailAddress)
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                } header: {
                    Text("Account")
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
                        Task { await signIn() }
                    } label: {
                        HStack {
                            if isLoading {
                                ProgressView()
                                    .frame(width: 20, height: 20)
                            }
                            Text("Log in")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(isLoading || email.isEmpty || password.isEmpty)

                    Button("Forgot password?") {
                        showForgotPassword = true
                    }
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("Forgot password")

                    Button("Create account") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        showRegister = true
                    }
                    .frame(maxWidth: .infinity)
                }

                Section("Or continue with") {
                    ForEach(visibleProviders, id: \.rawValue) { provider in
                        OAuthSignInButton(provider: provider, inFlight: oauthInFlight) {
                            handleOAuthTap(provider: provider)
                        }
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Login")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showRegister) {
                RegisterView()
                    .environmentObject(authState)
            }
            .sheet(isPresented: $showForgotPassword) {
                ForgotPasswordView()
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
        .task {
            await refreshOAuthVisibility()
        }
        .onAppear { errorMessage = nil }
        .onChange(of: showRegister) { _, isShowing in
            if isShowing {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
        }
    }

    private var visibleProviders: [OAuthProvider] {
        OAuthProvider.allCases.filter {
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
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
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
        } catch OAuthError.cancelled {
            // User cancelled — no surfaced error.
        } catch OAuthError.providerError(let message) {
            errorMessage = message
        } catch {
            errorMessage = "Sign-in with \(provider.displayName) failed. Please try again."
        }
    }

    private func signIn() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            try await authState.login(email: email, password: password)
        } catch APIError.server(let message) {
            errorMessage = message
        } catch APIError.status(401) {
            errorMessage = "Invalid email or password, or the server does not accept app login yet."
        } catch {
            errorMessage = "Connection failed. Please try again."
        }
    }
}
