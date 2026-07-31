//
//  SessionsView.swift
//  InterlinedList
//

import SwiftUI

struct SessionsView: View {
    @EnvironmentObject private var authState: AuthState
    @State private var sessions: [UserSession] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var actionError: String?

    var body: some View {
        Group {
            if isLoading && sessions.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error, sessions.isEmpty {
                ContentUnavailableView {
                    Label("Unable to load", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Retry") { Task { await load() } }
                }
            } else if sessions.isEmpty {
                ContentUnavailableView(
                    "No active sessions",
                    systemImage: "laptopcomputer.and.iphone",
                    description: Text("Devices signed in to your account will appear here.")
                )
            } else {
                List {
                    if let actionError {
                        Section {
                            Text(actionError).font(.ilMono()).foregroundStyle(.red)
                        }
                    }
                    Section {
                        ForEach(sessions) { session in
                            SessionRow(session: session)
                                .listRowBackground(session.isCurrent ? Color.accentColor.opacity(0.12) : nil)
                                .swipeActions(edge: .trailing) {
                                    if !session.isCurrent {
                                        Button(role: .destructive) {
                                            Task { await revoke(session) }
                                        } label: {
                                            Label("Revoke", systemImage: "xmark.circle")
                                        }
                                        .accessibilityLabel("Revoke \(session.deviceLabel ?? "Unknown device")")
                                    }
                                }
                        }
                    } footer: {
                        Text("Revoking a session signs that device out. Your current device can't be revoked here.")
                    }
                }
            }
        }
        .navigationTitle("Where You're Signed In")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            sessions = try await APIClient.shared.userSessions()
        } catch APIError.status(401) {
            authState.handleUnauthorized()
        } catch {
            self.error = "Could not load your sessions."
        }
    }

    private func revoke(_ session: UserSession) async {
        actionError = nil
        do {
            try await APIClient.shared.revokeSession(id: session.id)
            sessions.removeAll { $0.id == session.id }
        } catch APIError.status(401) {
            authState.handleUnauthorized()
        } catch {
            actionError = "Could not revoke \(session.deviceLabel ?? "that device")."
        }
    }
}

private struct SessionRow: View {
    let session: UserSession

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "laptopcomputer.and.iphone")
                .font(.title3)
                .foregroundStyle(session.isCurrent ? Color.accentColor : .secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(session.deviceLabel ?? "Unknown device")
                        .font(.ilBody(15))
                        .fontWeight(.medium)
                    if session.isCurrent {
                        Text("Current device")
                            .font(.ilMono(10))
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.15))
                            .clipShape(Capsule())
                            .accessibilityLabel("Current device")
                    }
                }
                if let subtitle = SessionRow.timestampText(session) {
                    Text(subtitle)
                        .font(.ilBody())
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }

    private static func timestampText(_ session: UserSession) -> String? {
        if let lastUsed = session.lastUsedAt, let relative = relative(from: lastUsed) {
            return "Last used \(relative)"
        }
        if let created = session.createdAt, let relative = relative(from: created) {
            return "Signed in \(relative)"
        }
        return nil
    }

    private static func relative(from iso: String) -> String? {
        guard !iso.isEmpty else { return nil }
        guard let date = fractional.date(from: iso) ?? plain.date(from: iso) else { return nil }
        return relativeFormatter.localizedString(for: date, relativeTo: Date())
    }

    private static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let plain = ISO8601DateFormatter()

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()
}

#Preview {
    NavigationStack {
        SessionsView()
            .environmentObject(AuthState())
    }
}
