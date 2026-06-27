//
//  OAuthSignInButton.swift
//  InterlinedList
//

import SwiftUI

/// A single provider row used in the "continue with" sections of `LoginView` and `RegisterView`.
/// Shows the provider icon + name, and a spinner while an OAuth round-trip is in flight.
struct OAuthSignInButton: View {
    let provider: OAuthProvider
    let inFlight: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: provider.systemImageName)
                    .frame(width: 24)
                Text(provider.displayName)
                Spacer()
                if inFlight {
                    ProgressView()
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(inFlight)
        .accessibilityLabel("Continue with \(provider.displayName)")
    }
}

#Preview {
    Form {
        Section("Or continue with") {
            ForEach(OAuthProvider.allCases, id: \.rawValue) { provider in
                OAuthSignInButton(provider: provider, inFlight: false) {}
            }
        }
    }
}
