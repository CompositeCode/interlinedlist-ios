//
//  MessagesInboxView.swift
//  InterlinedList
//

import SwiftUI

struct MessagesInboxView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authState: AuthState

    @State private var folder: DMFolder = .inbox
    @State private var messages: [DMMessage] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var showRecipientPicker = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Folder", selection: $folder) {
                    ForEach(DMFolder.allCases) { f in
                        Text(f.title).tag(f)
                    }
                }
                .pickerStyle(.segmented)
                .padding()
                .accessibilityLabel("Message folder")

                content
            }
            .navigationTitle("Messages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showRecipientPicker = true
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .accessibilityLabel("New message")
                }
            }
            .sheet(isPresented: $showRecipientPicker) {
                DMRecipientPickerView { user in
                    showRecipientPicker = false
                    pendingRecipient = user
                }
                .environmentObject(authState)
            }
            .navigationDestination(item: $selectedThreadUser) { user in
                DMThreadView(username: user.username, initialUser: user)
                    .environmentObject(authState)
            }
            .onChange(of: showRecipientPicker) { _, isShowing in
                // Push the thread only after the picker sheet has fully dismissed,
                // otherwise the push and the dismiss animation collide.
                if !isShowing, let user = pendingRecipient {
                    pendingRecipient = nil
                    selectedThreadUser = user
                }
            }
        }
        .task(id: folder) { await load() }
    }

    @State private var selectedThreadUser: DMUser?
    @State private var pendingRecipient: DMUser?

    @ViewBuilder
    private var content: some View {
        if isLoading && messages.isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error, messages.isEmpty {
            ContentUnavailableView {
                Label("Unable to load", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            } actions: {
                Button("Retry") { Task { await load() } }
            }
        } else if messages.isEmpty {
            ContentUnavailableView(
                emptyTitle,
                systemImage: "envelope",
                description: Text(emptyDescription)
            )
        } else {
            List {
                ForEach(messages) { message in
                    Button {
                        if let other = otherParty(for: message) {
                            selectedThreadUser = other
                        }
                    } label: {
                        DMInboxRow(message: message, folder: folder, selfId: authState.user?.id)
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.plain)
            .refreshable { await load() }
        }
    }

    private var emptyTitle: String {
        switch folder {
        case .inbox: return "No messages"
        case .sent: return "Nothing sent"
        case .deleted: return "Nothing deleted"
        }
    }

    private var emptyDescription: String {
        switch folder {
        case .inbox: return "Messages people send you appear here."
        case .sent: return "Messages you send appear here."
        case .deleted: return "Deleted messages appear here."
        }
    }

    private func otherParty(for message: DMMessage) -> DMUser? {
        message.otherParty(selfId: authState.user?.id)
    }

    private func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let response = try await APIClient.shared.directMessages(folder: folder)
            messages = response.items
        } catch APIError.status(401) {
            authState.handleUnauthorized()
        } catch APIError.server(let msg) {
            error = msg
        } catch {
            self.error = "Could not load messages."
        }
    }
}

/// One preview row in the inbox/sent/deleted list.
private struct DMInboxRow: View {
    let message: DMMessage
    let folder: DMFolder
    let selfId: String?

    private var other: DMUser? { message.otherParty(selfId: selfId) }
    private var showUnreadDot: Bool {
        folder == .inbox && !message.isRead && message.senderId != selfId
    }

    var body: some View {
        HStack(spacing: 12) {
            avatar
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(other?.displayNameOrUsername ?? "Unknown")
                        .font(.ilBody(15))
                        .fontWeight(showUnreadDot ? .bold : .medium)
                    Spacer()
                    Text(relativeTime(message.createdAt))
                        .font(.ilMono(10))
                        .foregroundStyle(.secondary)
                }
                if let preview = previewText, !preview.isEmpty {
                    Text(preview)
                        .font(.ilBody())
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            if showUnreadDot {
                Circle()
                    .fill(ILColor.primary)
                    .frame(width: 8, height: 8)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var previewText: String? {
        if let preview = message.preview, !preview.isEmpty { return preview }
        return message.body
    }

    @ViewBuilder
    private var avatar: some View {
        if let urlString = other?.avatar, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    Image(systemName: "person.circle.fill").resizable().scaledToFit()
                }
            }
            .frame(width: 40, height: 40)
            .clipShape(Circle())
        } else {
            Image(systemName: "person.circle.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 40, height: 40)
                .foregroundStyle(.secondary)
        }
    }

    private var accessibilityText: String {
        let name = other?.displayNameOrUsername ?? "Unknown"
        let unread = showUnreadDot ? "Unread. " : ""
        return "\(unread)\(name). \(previewText ?? "")"
    }

    private func relativeTime(_ iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) {
            let f = RelativeDateTimeFormatter()
            f.unitsStyle = .abbreviated
            return f.localizedString(for: date, relativeTo: Date())
        }
        return ""
    }
}

/// Recipient picker for starting a new conversation (mutual-follow set).
private struct DMRecipientPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authState: AuthState
    let onSelect: (DMUser) -> Void

    @State private var recipients: [DMUser] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var query = ""

    private var filtered: [DMUser] {
        guard !query.isEmpty else { return recipients }
        let lower = query.lowercased()
        return recipients.filter {
            $0.username.lowercased().contains(lower) ||
            ($0.displayName?.lowercased().contains(lower) ?? false)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && recipients.isEmpty {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error, recipients.isEmpty {
                    ContentUnavailableView {
                        Label("Unable to load", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Retry") { Task { await load() } }
                    }
                } else if recipients.isEmpty {
                    ContentUnavailableView(
                        "No one to message",
                        systemImage: "person.2.slash",
                        description: Text("You can only message people who follow you back.")
                    )
                } else {
                    List(filtered) { user in
                        Button {
                            onSelect(user)
                        } label: {
                            HStack(spacing: 12) {
                                avatar(user)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(user.displayNameOrUsername)
                                        .font(.ilBody(15))
                                        .fontWeight(.medium)
                                    Text("@\(user.username)")
                                        .font(.ilMono(10))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Message @\(user.username)")
                    }
                    .listStyle(.plain)
                    .searchable(text: $query, prompt: "Search people")
                }
            }
            .navigationTitle("New Message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .task { await load() }
    }

    @ViewBuilder
    private func avatar(_ user: DMUser) -> some View {
        if let urlString = user.avatar, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    Image(systemName: "person.circle.fill").resizable().scaledToFit()
                }
            }
            .frame(width: 36, height: 36)
            .clipShape(Circle())
        } else {
            Image(systemName: "person.circle.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 36, height: 36)
                .foregroundStyle(.secondary)
        }
    }

    private func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            recipients = try await APIClient.shared.dmRecipients()
        } catch APIError.status(401) {
            authState.handleUnauthorized()
        } catch {
            self.error = "Could not load people."
        }
    }
}

#Preview {
    MessagesInboxView()
        .environmentObject(AuthState())
}
