//
//  MessageDetailView.swift
//  InterlinedList
//

import SwiftUI

/// Full-message reading screen, pushed when a feed row's content is tapped. Shows
/// the untruncated content plus everything the list row summarizes or hides:
/// images, link previews, video, tags, and the cross-post destinations.
struct MessageDetailView: View {
    let message: Message
    let currentUserId: String?

    @State private var digCount: Int
    @State private var dugByMe: Bool
    @State private var showReplyCompose = false
    @State private var showRepostCompose = false
    @State private var showThread = false
    @State private var profileUsername: String?
    @State private var reportTarget: ReportTarget?
    @EnvironmentObject var authState: AuthState
    @EnvironmentObject var store: AppDataStore

    init(message: Message, currentUserId: String?) {
        self.message = message
        self.currentUserId = currentUserId
        _digCount = State(initialValue: message.digCount ?? 0)
        _dugByMe = State(initialValue: message.dugByMe ?? false)
    }

    private var isPrivate: Bool { message.publiclyVisible == false }
    private var canReport: Bool {
        guard let uid = currentUserId else { return false }
        return message.userId != uid
    }

    var body: some View {
        List {
            Section {
                header
                Text(message.content)
                    .font(.ilBody())
                    .textSelection(.enabled)
                if let tags = message.tags, !tags.isEmpty {
                    tagChips(tags)
                }
            }
            if message.hasPreviews {
                Section { previews }
            }
            if let urls = message.crossPostUrls, !urls.isEmpty {
                Section { CrossPostLinksView(urls: urls) }
            }
            Section { actions }
        }
        .navigationTitle("Post")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showReplyCompose) {
            ComposeView(replyTo: message)
                .environmentObject(authState)
                .environmentObject(store)
        }
        .sheet(isPresented: $showRepostCompose) {
            ComposeView(repostOf: message)
                .environmentObject(authState)
                .environmentObject(store)
        }
        .sheet(isPresented: $showThread) {
            MessageThreadView(rootMessage: message, currentUserId: currentUserId)
                .environmentObject(authState)
        }
        .sheet(isPresented: Binding(
            get: { profileUsername != nil },
            set: { if !$0 { profileUsername = nil } }
        )) {
            if let username = profileUsername { UserProfileView(username: username) }
        }
        .sheet(item: $reportTarget) { target in
            ReportSheet(target: target, onDismiss: { reportTarget = nil })
                .environmentObject(authState)
        }
    }

    private var header: some View {
        HStack {
            if let username = message.user?.username {
                Button {
                    profileUsername = username
                } label: {
                    Text(message.authorDisplay)
                        .font(.ilBody(15))
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
            } else {
                Text(message.authorDisplay)
                    .font(.ilBody(15))
                    .fontWeight(.medium)
            }
            if isPrivate {
                Image(systemName: "lock.fill")
                    .font(.ilMono(10))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Private")
            }
            Spacer()
            Text(formatDate(message.createdAt))
                .font(.ilMono())
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var previews: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let urls = message.imageUrls, !urls.isEmpty {
                ForEach(urls.prefix(8), id: \.self) { urlString in
                    if let url = URL(string: urlString) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable().scaledToFit()
                            case .failure:
                                Image(systemName: "photo")
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, minHeight: 120)
                            default:
                                ProgressView()
                                    .frame(maxWidth: .infinity, minHeight: 120)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(maxHeight: 320)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .accessibilityLabel("Attached image")
                    }
                }
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
                        .font(.ilMono())
                        .foregroundStyle(.secondary)
                    Link(destination: url) {
                        Label(first, systemImage: "play.rectangle")
                            .font(.ilMono())
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
        }
    }

    private var actions: some View {
        VStack(spacing: 12) {
            HStack(spacing: 20) {
                Button {
                    showReplyCompose = true
                } label: {
                    Image(systemName: "arrowshape.turn.up.left")
                        .font(.ilMono())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Reply")
                HStack(spacing: 4) {
                    Button {
                        Task { await toggleDig() }
                    } label: {
                        Image(systemName: dugByMe ? "hand.thumbsup.fill" : "hand.thumbsup")
                            .font(.ilMono())
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(dugByMe ? "Dug" : "Dig")
                    if digCount > 0 {
                        Text("\(digCount)")
                            .font(.ilMono())
                            .foregroundStyle(.secondary)
                    }
                }
                Button {
                    showRepostCompose = true
                } label: {
                    Image(systemName: "arrow.2.squarepath")
                        .font(.ilMono())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Repost")
                if canReport {
                    Menu {
                        Button(role: .destructive) {
                            reportTarget = .message(id: message.id)
                        } label: {
                            Label("Report…", systemImage: "flag")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.ilMono())
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("More options")
                }
                Spacer()
            }
            Button {
                showThread = true
            } label: {
                HStack {
                    Label("View thread", systemImage: "bubble.left.and.bubble.right")
                        .font(.ilBody(15))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.ilMono())
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows replies to this post")
        }
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

    private func toggleDig() async {
        do {
            let result = dugByMe
                ? try await APIClient.shared.undig(messageId: message.id)
                : try await APIClient.shared.dig(messageId: message.id)
            digCount = result.digCount
            dugByMe = result.dugByMe
        } catch APIError.status(401) {
            authState.handleUnauthorized()
        } catch {
            // Silently ignore dig errors — not critical
        }
    }

    private func formatDate(_ iso: String) -> String {
        if let date = detailISOFullFormatter.date(from: iso) ?? detailISOBasicFormatter.date(from: iso) {
            return detailRelativeDateFormatter.localizedString(for: date, relativeTo: Date())
        }
        return iso
    }
}

private let detailISOFullFormatter: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()
private let detailISOBasicFormatter = ISO8601DateFormatter()
private let detailRelativeDateFormatter: RelativeDateTimeFormatter = {
    let f = RelativeDateTimeFormatter()
    f.unitsStyle = .abbreviated
    return f
}()

#Preview {
    NavigationStack {
        MessageDetailView(
            message: Message(
                id: "1",
                content: "This is the full content of a message shown on the detail screen. It can be long enough that the feed would have truncated it, but here you read the whole thing.",
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
                crossPostUrls: [
                    CrossPostUrl(platform: "mastodon", url: "https://techhub.social/@x/1", instanceName: "techhub.social", instanceUrl: nil, statusId: "1", cid: nil, uri: nil)
                ]
            ),
            currentUserId: "user2"
        )
        .environmentObject(AuthState())
        .environmentObject(AppDataStore())
    }
}
