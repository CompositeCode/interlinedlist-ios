//
//  ResetPasswordView.swift
//  InterlinedList
//

import SwiftUI

struct ResetPasswordView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var token: String
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var didReset = false

    init(token: String = "") {
        _token = State(initialValue: token)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Paste the reset token from your email or open the link in this app to fill it in automatically.")
                        .font(.ilBody(15))
                        .foregroundStyle(.secondary)
                }
                Section("Reset token") {
                    TextField("Token", text: $token)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .disabled(didReset)
                }
                Section {
                    SecureField("New password", text: $password)
                        .textContentType(.newPassword)
                        .disabled(didReset)
                    SecureField("Confirm new password", text: $confirmPassword)
                        .textContentType(.newPassword)
                        .disabled(didReset)
                } header: {
                    Text("New password")
                } footer: {
                    Text("Password must be at least 8 characters.")
                }
                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.ilMono())
                    }
                }
                if didReset {
                    Section {
                        Label("Password reset. You can now log in.", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(ILColor.primary)
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
                                Text("Reset password")
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .disabled(isLoading || !canSubmit)
                        .accessibilityLabel("Reset password")
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Reset password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(didReset ? "Done" : "Cancel") { dismiss() }
                }
            }
        }
    }

    private var canSubmit: Bool {
        !token.isEmpty && password.count >= 8 && password == confirmPassword
    }

    private func submit() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            try await APIClient.shared.resetPassword(
                token: token.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password
            )
            didReset = true
        } catch APIError.server(let message) {
            errorMessage = message
        } catch APIError.status(400) {
            errorMessage = "Reset link is invalid or expired."
        } catch APIError.status(let code) {
            errorMessage = "Reset failed (HTTP \(code))."
        } catch {
            errorMessage = "Connection failed. Please try again."
        }
    }
}

#Preview {
    ResetPasswordView(token: "demo-token")
}
