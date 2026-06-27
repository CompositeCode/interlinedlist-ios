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
                await loadReplies()
            }
            .refreshable {
                await loadReplies()
            }
            .sheet(isPresented: $showReplyCompose, onDismiss: { Task { await loadReplies() } }) {
                ComposeView(replyTo: rootMessage)
                    .environmentObject(authState)
            }
        }
    }

    private var rootMessageView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(rootMessage.authorDisplay)
                    .font(.subheadline)
                    .fontWeight(.medium)
                if rootMessage.publiclyVisible == false {
                    Image(systemName: "lock.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(formatDate(rootMessage.createdAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(rootMessage.content)
                .font(.body)
            if let tags = rootMessage.tags, !tags.isEmpty {
                tagChips(tags)
            }
        }
        .padding(.vertical, 4)
    }

    private func replyRow(_ reply: Message) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(reply.authorDisplay)
                    .font(.subheadline)
                    .fontWeight(.medium)
                if reply.publiclyVisible == false {
                    Image(systemName: "lock.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(formatDate(reply.createdAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(reply.content)
                .font(.body)
            if let tags = reply.tags, !tags.isEmpty {
                tagChips(tags)
            }
        }
        .padding(.vertical, 4)
    }

    private func tagChips(_ tags: [String]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(tags, id: \.self) { tag in
                    Text(tag)
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color(.secondarySystemFill))
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
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) {
            let f = RelativeDateTimeFormatter()
            f.unitsStyle = .abbreviated
            return f.localizedString(for: date, relativeTo: Date())
        }
        return iso
    }
}

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
            dugByMe: false
        ),
        currentUserId: "user1"
    )
    .environmentObject(AuthState())
}
