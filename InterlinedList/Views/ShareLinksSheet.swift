//
//  ShareLinksSheet.swift
//  InterlinedList
//

import SwiftUI
import UIKit

/// Owner-facing sheet for managing tokenized share-links on a list or document.
/// Lists active links (role, expiry, copy, revoke) and — for subscribers —
/// offers a control to create a new link. Non-subscribing owners can still see
/// and revoke existing links; the create control is hidden rather than paywalled.
struct ShareLinksSheet: View {
    let kind: ShareResourceKind
    let resourceId: String
    let title: String

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authState: AuthState
    @State private var links: [ShareLink] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var actionError: String?
    @State private var newRole: WatcherRole = .watcher
    @State private var useExpiry = false
    @State private var expiryDate = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
    @State private var isCreating = false

    private var canCreate: Bool { authState.user?.isSubscriber == true }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && links.isEmpty {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error, links.isEmpty {
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
            .navigationTitle("Share")
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

            if canCreate {
                createSection
            }

            Section("Active links") {
                if links.isEmpty {
                    Text("No share links yet.")
                        .font(.ilBody(15)).foregroundStyle(.secondary)
                } else {
                    ForEach(links) { link in
                        ShareLinkRow(link: link, onCopy: { copy(link) })
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    Task { await revoke(link) }
                                } label: {
                                    Label("Revoke", systemImage: "link.badge.plus")
                                }
                            }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var createSection: some View {
        Section("Create link") {
            Picker("Role", selection: $newRole) {
                ForEach(WatcherRole.allCases, id: \.self) { role in
                    Text(role.label).tag(role)
                }
            }
            .pickerStyle(.segmented)
            Text(newRole.detail(for: kind.singularLabel)).font(.ilMono()).foregroundStyle(.secondary)

            Toggle("Set expiry", isOn: $useExpiry)
                .accessibilityLabel("Set an expiry date for the link")
            if useExpiry {
                DatePicker("Expires", selection: $expiryDate, in: Date()..., displayedComponents: [.date])
            }

            Button {
                Task { await create() }
            } label: {
                HStack {
                    if isCreating { ProgressView() }
                    Text("Create share link")
                }
            }
            .disabled(isCreating)
            .accessibilityLabel("Create share link")
        }
    }

    private func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            links = try await APIClient.shared.shareLinks(kind: kind, id: resourceId)
        } catch APIError.status(401) {
            authState.handleUnauthorized()
        } catch {
            self.error = "Could not load share links."
        }
    }

    private func create() async {
        isCreating = true
        actionError = nil
        defer { isCreating = false }
        let expiresAt = useExpiry ? ISO8601DateFormatter().string(from: expiryDate) : nil
        do {
            let link = try await APIClient.shared.createShareLink(kind: kind, id: resourceId, role: newRole, expiresAt: expiresAt)
            links.insert(link, at: 0)
        } catch APIError.status(401) {
            authState.handleUnauthorized()
        } catch APIError.server(let msg) {
            actionError = msg
        } catch {
            actionError = "Could not create share link."
        }
    }

    private func revoke(_ link: ShareLink) async {
        actionError = nil
        do {
            try await APIClient.shared.revokeShareLink(kind: kind, id: resourceId, token: link.token)
            links.removeAll { $0.token == link.token }
        } catch APIError.status(401) {
            authState.handleUnauthorized()
        } catch APIError.server(let msg) {
            actionError = msg
        } catch {
            actionError = "Could not revoke this link."
        }
    }

    private func copy(_ link: ShareLink) {
        UIPasteboard.general.string = link.url
    }
}

private struct ShareLinkRow: View {
    let link: ShareLink
    let onCopy: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text((link.shareRole ?? .watcher).label)
                    .font(.ilMono())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(ILColor.surface2)
                    .clipShape(Capsule())
                Text(expiryText)
                    .font(.ilBody(13))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                onCopy()
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Copy link URL")
        }
        .padding(.vertical, 2)
    }

    private var expiryText: String {
        guard let expiresAt = link.expiresAt, !expiresAt.isEmpty else { return "No expiry" }
        let date = ShareLinkRow.fractional.date(from: expiresAt) ?? ShareLinkRow.plain.date(from: expiresAt)
        guard let date else { return "Expires \(expiresAt)" }
        return "Expires \(ShareLinkRow.display.string(from: date))"
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
    ShareLinksSheet(kind: .lists, resourceId: "list-1", title: "My List")
        .environmentObject(AuthState())
}
