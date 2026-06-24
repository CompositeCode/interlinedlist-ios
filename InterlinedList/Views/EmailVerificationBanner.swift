//
//  EmailVerificationBanner.swift
//  InterlinedList
//

import SwiftUI

/// Inline banner shown beneath the top bar when the signed-in user's email is unverified.
/// Tapping "Resend" calls `POST /api/auth/send-verification-email`. Renders nothing when the
/// user is verified or the verification state is unknown (nil) to avoid nagging on transient loads.
struct EmailVerificationBanner: View {
    @EnvironmentObject var authState: AuthState
    @State private var isSending = false
    @State private var didSend = false
    @State private var errorMessage: String?

    private var isUnverified: Bool {
        authState.user?.emailVerified == false
    }

    var body: some View {
        if isUnverified {
            HStack(spacing: 10) {
                Image(systemName: "envelope.badge.fill")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(didSend ? "Verification email sent" : "Verify your email address")
                        .font(.subheadline.weight(.medium))
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    } else if didSend {
                        Text("Check your inbox for the confirmation link.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                if !didSend {
                    Button {
                        Task { await resend() }
                    } label: {
                        if isSending {
                            ProgressView().frame(width: 18, height: 18)
                        } else {
                            Text("Resend").font(.subheadline.weight(.semibold))
                        }
                    }
                    .buttonStyle(.borderless)
                    .disabled(isSending)
                    .accessibilityLabel("Resend verification email")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.12))
        }
    }

    private func resend() async {
        errorMessage = nil
        isSending = true
        defer { isSending = false }
        do {
            try await APIClient.shared.sendVerificationEmail()
            didSend = true
        } catch APIError.server(let message) {
            errorMessage = message
        } catch {
            errorMessage = "Couldn't send the email. Please try again."
        }
    }
}

#Preview {
    EmailVerificationBanner()
        .environmentObject(AuthState())
}
