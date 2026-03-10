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
                                    .scaleEffect(0.9)
                            }
                            Text("Create account")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(isLoading || email.isEmpty || username.isEmpty || password.count < 8)
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
        }
        .onAppear { errorMessage = nil }
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
