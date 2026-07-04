//
//  ForgotPasswordView.swift
//  InterlinedList
//

import SwiftUI

struct ForgotPasswordView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var didRequest = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Enter your email and we'll send you a link to reset your password.")
                        .font(.ilBody(15))
                        .foregroundStyle(.secondary)
                }
                Section {
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .autocapitalization(.none)
                        .keyboardType(.emailAddress)
                        .disabled(didRequest)
                }
                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.ilMono())
                    }
                }
                if didRequest {
                    Section {
                        Label("If an account exists for that email, a reset link has been sent.", systemImage: "envelope.badge")
                            .foregroundStyle(.secondary)
                            .font(.ilBody(15))
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
                                Text("Send reset link")
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .disabled(isLoading || email.isEmpty)
                        .accessibilityLabel("Send password reset link")
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Forgot password")
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
            try await APIClient.shared.forgotPassword(email: email.trimmingCharacters(in: .whitespacesAndNewlines))
            didRequest = true
        } catch APIError.server(let message) {
            errorMessage = message
        } catch {
            errorMessage = "Could not send reset email. Please try again."
        }
    }
}

#Preview {
    ForgotPasswordView()
}
