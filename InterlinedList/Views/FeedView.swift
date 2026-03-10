//
//  FeedView.swift
//  InterlinedList
//

import SwiftUI

struct FeedView: View {
    @EnvironmentObject var authState: AuthState
    @State private var messages: [Message] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var pagination: Pagination?
    @State private var showPreviews = true
    @State private var replyToMessage: Message?
    @State private var messageToDelete: Message?
    @State private var deleteError: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && messages.isEmpty {
                    ProgressView("Loading messages…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .frame(minWidth: 44, minHeight: 44)
                } else if let error = errorMessage, messages.isEmpty {
                    ContentUnavailableView {
                        Label("Unable to load", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Retry") {
                            Task { await loadMessages() }
                        }
                    }
                } else {
                    List {
                        Section {
                            Toggle("Show previews", isOn: $showPreviews)
                        }
                        ForEach(messages) { message in
                            MessageRow(
                                message: message,
                                currentUserId: authState.user?.id,
                                showPreviews: showPreviews,
                                onReply: {
                                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                                    replyToMessage = message
                                },
                                onDelete: {
                                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                                    messageToDelete = message
                                }
                            )
                        }
                        if let pagination = pagination, pagination.hasMore, !isLoading {
                            HStack {
                                Spacer()
                                ProgressView()
                                    .frame(width: 24, height: 24)
                                Spacer()
                            }
                            .onAppear {
                                Task { await loadMore() }
                            }
                        }
                    }
                    .refreshable {
                        await loadMessages()
                    }
                }
            }
            .navigationTitle("InterlinedList")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        Image("Logo")
                            .resizable()
                            .frame(width: 28, height: 28)
                            .clipped()
                        Text("InterlinedList")
                            .font(.headline)
                    }
                }
            }
            .task {
                await loadMessages()
            }
            .onChange(of: authState.user?.id) { _, _ in
                if authState.isLoggedIn {
                    Task { await loadMessages() }
                }
            }
            .sheet(item: $replyToMessage, onDismiss: { replyToMessage = nil }) { message in
                ComposeView(replyTo: message)
                    .environmentObject(authState)
            }
            .alert("Delete message?", isPresented: Binding(
                get: { messageToDelete != nil },
                set: { if !$0 { messageToDelete = nil; deleteError = nil } }
            )) {
                Button("Cancel", role: .cancel) {
                    messageToDelete = nil
                    deleteError = nil
                }
                Button("Delete", role: .destructive) {
                    guard let msg = messageToDelete else { return }
                    deleteError = nil
                    Task { await deleteMessage(msg) }
                }
            } message: {
                Text(deleteError ?? "This cannot be undone.")
            }
        }
    }

    private func deleteMessage(_ message: Message) async {
        do {
            try await APIClient.shared.deleteMessage(id: message.id)
            messageToDelete = nil
            messages.removeAll { $0.id == message.id }
        } catch APIError.status(401) {
            authState.handleUnauthorized()
            messageToDelete = nil
        } catch APIError.server(let text) {
            deleteError = text
        } catch {
            deleteError = "Failed to delete."
        }
    }

    private func loadMessages() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            let (list, pag) = try await APIClient.shared.messages(limit: 50, offset: 0)
            messages = list
            pagination = pag
        } catch APIError.status(401) {
            authState.handleUnauthorized()
        } catch APIError.server(let message) {
            errorMessage = message
        } catch {
            errorMessage = "Connection failed. Please try again."
        }
    }

    private func loadMore() async {
        guard let pag = pagination, pag.hasMore else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let (list, pag) = try await APIClient.shared.messages(limit: 50, offset: messages.count)
            messages.append(contentsOf: list)
            pagination = pag
        } catch {
            errorMessage = "Failed to load more."
        }
    }
}

struct MessageRow: View {
    let message: Message
    let currentUserId: String?
    let showPreviews: Bool
    let onReply: () -> Void
    let onDelete: () -> Void

    private var canDelete: Bool {
        guard let uid = currentUserId else { return false }
        return message.userId == uid
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(message.authorDisplay)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Text(formatDate(message.createdAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(message.content)
                .font(.body)
            if showPreviews && message.hasPreviews {
                previewSection
            }
            HStack(spacing: 12) {
                Button {
                    onReply()
                } label: {
                    Label("Reply", systemImage: "arrowshape.turn.up.left")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                if canDelete {
                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Label("Delete", systemImage: "trash")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let urls = message.imageUrls, !urls.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(urls.prefix(8), id: \.self) { urlString in
                            if let url = URL(string: urlString) {
                                AsyncImage(url: url) { phase in
                                    switch phase {
                                    case .success(let image):
                                        image
                                            .resizable()
                                            .scaledToFill()
                                    case .failure:
                                        Image(systemName: "photo")
                                            .foregroundStyle(.secondary)
                                    default:
                                        ProgressView()
                                            .frame(width: 60, height: 60)
                                    }
                                }
                                .frame(width: 80, height: 80)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                        }
                    }
                }
                .frame(height: 86)
            }
            if let links = message.linkMetadata?.links, !links.isEmpty {
                ForEach(Array(links.enumerated()), id: \.offset) { _, link in
                    if let meta = link.metadata {
                        LinkPreviewBlock(link: link, meta: meta)
                    }
                }
            }
            if let urls = message.videoUrls, !urls.isEmpty, let first = urls.first, let url = URL(string: first) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Video")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Link(destination: url) {
                        Label(first, systemImage: "play.rectangle")
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
        }
        .padding(.top, 4)
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

private struct LinkPreviewBlock: View {
    let link: LinkMetadataItem
    let meta: LinkMetadataItemContent

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let thumb = meta.thumbnail, let url = URL(string: thumb) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        EmptyView()
                    default:
                        ProgressView()
                            .frame(width: 44, height: 44)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 120)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            if let title = meta.title, !title.isEmpty {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(2)
            }
            if let desc = meta.description, !desc.isEmpty {
                Text(desc)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(8)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
