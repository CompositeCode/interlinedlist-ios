//
//  MessageThreadView.swift
//  InterlinedList
//

import SwiftUI

struct MessageThreadView: View {
    let rootMessage: Message
    let currentUserId: String?

    @State private var replies: [Message] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showReplyCompose = false
    @State private var reportTarget: ReportTarget? = nil
    @ObservedObject private var muteStore = MuteStore.shared
    @State private var muteTarget: MuteTarget?
    @State private var muteError: String?
    @EnvironmentObject var authState: AuthState

    var body: some View {
        NavigationStack {
            List {
                Section {
                    rootMessageView
                }
                Section("Replies") {
                    if isLoading && replies.isEmpty {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    } else if let error = errorMessage, replies.isEmpty {
                        ContentUnavailableView {
                            Label("Unable to load replies", systemImage: "exclamationmark.triangle")
                        } description: {
                            Text(error)
                        } actions: {
                            Button("Retry") {
                                Task { await loadReplies() }
                            }
                        }
                    } else if replies.isEmpty && !isLoading {
                        ContentUnavailableView {
                            Label("No Replies", systemImage: "bubble.left")
                        } description: {
                            Text("Be the first to reply.")
                        }
                    } else {
                        ForEach(replies) { reply in
                            replyRow(reply)
                        }
                    }
                }
            }
            .navigationTitle("Thread")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showReplyCompose = true
                    } label: {
                        Image(systemName: "arrowshape.turn.up.left")
                    }
                }
            }
            .task {
                async let replies: Void = loadReplies()
                async let mutes: Void = seedMutes()
                _ = await (replies, mutes)
            }
            .refreshable {
                await loadReplies()
            }
            .sheet(isPresented: $showReplyCompose, onDismiss: { Task { await loadReplies() } }) {
                ComposeView(replyTo: rootMessage)
                    .environmentObject(authState)
            }
            .sheet(item: $reportTarget) { target in
                ReportSheet(target: target, onDismiss: { reportTarget = nil })
                    .environmentObject(authState)
            }
            .muteConfirmation(target: $muteTarget, errorMessage: $muteError) { target in
                Task { await mute(target) }
            }
        }
    }

    private func seedMutes() async {
        try? await muteStore.loadIfNeeded()
    }

    private func mute(_ target: MuteTarget) async {
        muteError = nil
        do {
            try await muteStore.mute(userId: target.id, username: target.username, displayName: target.displayName)
        } catch APIError.status(401) {
            authState.handleUnauthorized()
        } catch {
            muteError = "Could not mute @\(target.username)."
        }
    }

    private func unmute(_ reply: Message) async {
        muteError = nil
        do {
            try await muteStore.unmute(userId: reply.userId)
        } catch APIError.status(401) {
            authState.handleUnauthorized()
        } catch {
            muteError = "Could not unmute @\(reply.user?.username ?? "user")."
        }
    }

    private var rootMessageView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(rootMessage.authorDisplay)
                    .font(.ilBody(15))
                    .fontWeight(.medium)
                if rootMessage.publiclyVisible == false {
                    Image(systemName: "lock.fill")
                        .font(.ilMono(10))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(formatDate(rootMessage.createdAt))
                    .font(.ilMono())
                    .foregroundStyle(.secondary)
            }
            Text(rootMessage.content)
                .font(.ilBody())
            if let tags = rootMessage.tags, !tags.isEmpty {
                tagChips(tags)
            }
            if let urls = rootMessage.crossPostUrls, !urls.isEmpty {
                CrossPostLinksView(urls: urls)
            }
        }
        .padding(.vertical, 4)
    }

    private func replyRow(_ reply: Message) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(reply.authorDisplay)
                    .font(.ilBody(15))
                    .fontWeight(.medium)
                if reply.publiclyVisible == false {
                    Image(systemName: "lock.fill")
                        .font(.ilMono(10))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(formatDate(reply.createdAt))
                    .font(.ilMono())
                    .foregroundStyle(.secondary)
            }
            Text(reply.content)
                .font(.ilBody())
            if let tags = reply.tags, !tags.isEmpty {
                tagChips(tags)
            }
            if reply.userId != currentUserId {
                HStack {
                    Spacer()
                    Menu {
                        Button(role: .destructive) {
                            reportTarget = .message(id: reply.id)
                        } label: {
                            Label("Report…", systemImage: "flag")
                        }
                        if muteStore.isMuted(reply.userId) {
                            Button {
                                Task { await unmute(reply) }
                            } label: {
                                Label("Unmute user", systemImage: "speaker.wave.2")
                            }
                            .accessibilityLabel("Unmute user")
                        } else {
                            Button {
                                muteTarget = MuteTarget(message: reply)
                            } label: {
                                Label("Mute user", systemImage: "speaker.slash")
                            }
                            .accessibilityLabel("Mute user")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.ilMono())
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("More options")
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func tagChips(_ tags: [String]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(tags, id: \.self) { tag in
                    Text(tag)
                        .font(.ilMono(10))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(ILColor.surface2)
                        .clipShape(Capsule())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func loadReplies() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            replies = try await APIClient.shared.replies(messageId: rootMessage.id)
        } catch APIError.status(401) {
            errorMessage = "Authentication required."
        } catch APIError.server(let msg) {
            errorMessage = msg
        } catch {
            errorMessage = "Failed to load replies."
        }
    }

    private func formatDate(_ iso: String) -> String {
        if let date = threadISOFullFormatter.date(from: iso) ?? threadISOBasicFormatter.date(from: iso) {
            return threadRelativeDateFormatter.localizedString(for: date, relativeTo: Date())
        }
        return iso
    }
}

private let threadISOFullFormatter: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()
private let threadISOBasicFormatter = ISO8601DateFormatter()
private let threadRelativeDateFormatter: RelativeDateTimeFormatter = {
    let f = RelativeDateTimeFormatter()
    f.unitsStyle = .abbreviated
    return f
}()

#Preview {
    MessageThreadView(
        rootMessage: Message(
            id: "1",
            content: "This is the root message for the thread.",
            publiclyVisible: true,
            userId: "user1",
            createdAt: "2025-01-01T00:00:00Z",
            updatedAt: nil,
            user: MessageUser(id: "user1", username: "testuser", displayName: "Test User", avatar: nil),
            imageUrls: nil,
            videoUrls: nil,
            linkMetadata: nil,
            parentId: nil,
            scheduledAt: nil,
            tags: ["swift", "ios"],
            digCount: 3,
            dugByMe: false,
            crossPostUrls: nil
        ),
        currentUserId: "user1"
    )
    .environmentObject(AuthState())
}
