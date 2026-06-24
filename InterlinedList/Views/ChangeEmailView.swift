//
//  ChangeEmailView.swift
//  InterlinedList
//

import SwiftUI

struct ChangeEmailView: View {
    @EnvironmentObject var authState: AuthState
    @Environment(\.dismiss) private var dismiss
    @State private var newEmail = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var didRequest = false

    var body: some View {
        NavigationStack {
            Form {
                if let current = authState.user?.email {
                    Section("Current email") {
                        Text(current)
                            .foregroundStyle(.secondary)
                    }
                }
                Section("New email") {
                    TextField("New email", text: $newEmail)
                        .textContentType(.emailAddress)
                        .autocapitalization(.none)
                        .keyboardType(.emailAddress)
                        .disabled(didRequest)
                }
                Section("Confirm password") {
                    SecureField("Current password", text: $password)
                        .textContentType(.password)
                        .disabled(didRequest)
                }
                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
                if didRequest {
                    Section {
                        Label("Check your new email for a verification link.", systemImage: "envelope.badge")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section {
                        Button {
                            Task { await submit() }
                        } label: {
                            HStack {
                                if isLoading {
                                    ProgressView().frame(width: 20, height: 20)
                                }
                                Text("Request email change")
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .disabled(isLoading || newEmail.isEmpty || password.isEmpty)
                        .accessibilityLabel("Request email change")
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Change email")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(didRequest ? "Done" : "Cancel") { dismiss() }
                }
            }
        }
    }

    private func submit() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            try await APIClient.shared.requestEmailChange(
                newEmail: newEmail.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password
            )
            didRequest = true
        } catch APIError.server(let message) {
            errorMessage = message
        } catch APIError.status(401) {
            errorMessage = "Incorrect password."
        } catch APIError.status(let code) {
            errorMessage = "Request failed (HTTP \(code))."
        } catch {
            errorMessage = "Connection failed. Please try again."
        }
    }
}

#Preview {
    ChangeEmailView()
        .environmentObject(AuthState())
}
