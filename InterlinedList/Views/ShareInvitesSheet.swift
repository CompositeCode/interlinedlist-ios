//
//  ShareInvitesSheet.swift
//  InterlinedList
//

import SwiftUI

/// Owner-facing sheet for managing email share-invites on a list or document.
/// Lists pending/accepted invites (email, role, expiry) with swipe-to-revoke,
/// and — for subscribers — a form to send a new invite. Non-subscribing owners
/// can still see and revoke existing invites; the send form is hidden rather
/// than paywalled.
///
/// Recipients claim their invite on the **web** (the claim flow is session-only),
/// so iOS only ever sends, lists, and revokes invites here.
struct ShareInvitesSheet: View {
    let kind: ShareResourceKind
    let resourceId: String
    let title: String

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authState: AuthState
    @State private var invites: [ShareInvite] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var actionError: String?
    @State private var newEmail = ""
    @State private var newRole: WatcherRole = .watcher
    @State private var useExpiry = false
    @State private var expiryDate = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
    @State private var isSending = false

    private var canInvite: Bool { authState.user?.isSubscriber == true }

    private var trimmedEmail: String { newEmail.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isEmailValid: Bool {
        let email = trimmedEmail
        guard let at = email.firstIndex(of: "@"), at != email.startIndex else { return false }
        let domain = email[email.index(after: at)...]
        return domain.contains(".") && !domain.hasSuffix(".")
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && invites.isEmpty {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error, invites.isEmpty {
                    ContentUnavailableView {
                        Label("Unable to load", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Retry") { Task { await load() } }
                    }
                } else {
                    content
                }
            }
            .navigationTitle("Invite by email")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await load() }
        }
    }

    @ViewBuilder
    private var content: some View {
        List {
            Section {
                Text(title).font(.ilBody()).foregroundStyle(.secondary)
            }

            if let actionError {
                Section { Text(actionError).font(.ilMono()).foregroundStyle(.red) }
            }

            if canInvite {
                inviteSection
            }

            Section("Invites") {
                if invites.isEmpty {
                    Text("No invites sent yet.")
                        .font(.ilBody(15)).foregroundStyle(.secondary)
                } else {
                    ForEach(invites) { invite in
                        ShareInviteRow(invite: invite)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    Task { await revoke(invite) }
                                } label: {
                                    Label("Revoke", systemImage: "envelope.badge")
                                }
                            }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var inviteSection: some View {
        Section("Send invite") {
            TextField("Email address", text: $newEmail)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textContentType(.emailAddress)
                .accessibilityLabel("Recipient email address")

            Picker("Role", selection: $newRole) {
                ForEach(WatcherRole.allCases, id: \.self) { role in
                    Text(role.label).tag(role)
                }
            }
            .pickerStyle(.segmented)
            Text(newRole.detail(for: kind.singularLabel)).font(.ilMono()).foregroundStyle(.secondary)

            Toggle("Set expiry", isOn: $useExpiry)
                .accessibilityLabel("Set an expiry date for the invite")
            if useExpiry {
                DatePicker("Expires", selection: $expiryDate, in: Date()..., displayedComponents: [.date])
            }

            Button {
                Task { await send() }
            } label: {
                HStack {
                    if isSending { ProgressView() }
                    Text("Send invite")
                }
            }
            .disabled(isSending || !isEmailValid)
            .accessibilityLabel("Send invite")
        }
    }

    private func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            invites = try await APIClient.shared.shareInvites(kind: kind, id: resourceId)
        } catch APIError.status(401) {
            authState.handleUnauthorized()
        } catch {
            self.error = "Could not load invites."
        }
    }

    private func send() async {
        isSending = true
        actionError = nil
        defer { isSending = false }
        let expiresAt = useExpiry ? ISO8601DateFormatter().string(from: expiryDate) : nil
        do {
            _ = try await APIClient.shared.createShareInvite(kind: kind, id: resourceId, email: trimmedEmail, role: newRole, expiresAt: expiresAt)
            newEmail = ""
            await load()
        } catch APIError.status(401) {
            authState.handleUnauthorized()
        } catch APIError.status(403) {
            // Subscriber-gated server-side. The UI already hides the form for free
            // users, so a 403 here is an edge case; surface a neutral message
            // rather than the backend's "Subscribe to…" copy.
            actionError = "You can't send invites right now."
        } catch {
            actionError = "Could not send this invite."
        }
    }

    private func revoke(_ invite: ShareInvite) async {
        actionError = nil
        do {
            try await APIClient.shared.revokeShareInvite(kind: kind, id: resourceId, token: invite.token)
            invites.removeAll { $0.token == invite.token }
        } catch APIError.status(401) {
            authState.handleUnauthorized()
        } catch APIError.server(let msg) {
            actionError = msg
        } catch {
            actionError = "Could not revoke this invite."
        }
    }
}

private struct ShareInviteRow: View {
    let invite: ShareInvite

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(invite.email)
                    .font(.ilBody())
                HStack(spacing: 8) {
                    Text((invite.shareRole ?? .watcher).label)
                        .font(.ilMono())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(ILColor.surface2)
                        .clipShape(Capsule())
                    Text(statusText)
                        .font(.ilMono())
                        .foregroundStyle(invite.accepted == true ? Color.green : .secondary)
                }
                Text(expiryText)
                    .font(.ilBody(13))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }

    private var statusText: String { invite.accepted == true ? "Accepted" : "Pending" }

    private var expiryText: String {
        guard let expiresAt = invite.expiresAt, !expiresAt.isEmpty else { return "No expiry" }
        let date = ShareInviteRow.fractional.date(from: expiresAt) ?? ShareInviteRow.plain.date(from: expiresAt)
        guard let date else { return "Expires \(expiresAt)" }
        return "Expires \(ShareInviteRow.display.string(from: date))"
    }

    private static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let plain = ISO8601DateFormatter()

    private static let display: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()
}

#Preview {
    ShareInvitesSheet(kind: .lists, resourceId: "list-1", title: "My List")
        .environmentObject(AuthState())
}
