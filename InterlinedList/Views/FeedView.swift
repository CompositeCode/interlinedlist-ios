//
//  FeedView.swift
//  InterlinedList
//

import SwiftUI

struct FeedView: View {
    @EnvironmentObject var authState: AuthState
    @EnvironmentObject var store: AppDataStore
    @State private var messages: [Message] = []
    @State private var isLoading = true
    @State private var syncedFromStore = false
    @State private var errorMessage: String?
    @State private var pagination: Pagination?
    @State private var showPreviews = true
    @State private var showOnlyMine = false
    @State private var tagFilter: String? = nil
    @State private var messageToDelete: Message?
    @State private var deleteError: String?
    @State private var showCompose = false
    @State private var messageToEdit: Message?
    @State private var messageToRepost: Message?
    @State private var threadMessage: Message?
    @State private var digStates: [String: (count: Int, dugByMe: Bool)] = [:]
    @State private var locallyToggled: Set<String> = []
    @State private var profileUsername: String? = nil
    @State private var showScheduled = false
    @State private var searchText = ""
    @State private var searchResults: [Message] = []
    @State private var isSearching = false
    @State private var searchPerformed = false
    @State private var reportTarget: ReportTarget? = nil
    @State private var blockedUserIds: Set<String> = []

    private var distinctTags: [String] {
        var seen = Set<String>()
        return messages.compactMap { $0.tags }.flatMap { $0 }.filter { seen.insert($0).inserted }
    }

    @ViewBuilder
    private var feedContent: some View {
        if !searchText.isEmpty {
            searchResultsList
        } else if isLoading && messages.isEmpty {
            FeedSkeletonView()
        } else if let error = errorMessage, messages.isEmpty {
            ContentUnavailableView {
                Label("Unable to load", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            } actions: {
                Button("Retry") { Task { await loadMessages() } }
            }
        } else {
            messageList
        }
    }

    @ViewBuilder
    private var searchResultsList: some View {
        if isSearching {
            ProgressView("Searching…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if searchResults.isEmpty && searchPerformed {
            ContentUnavailableView.search(text: searchText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(searchResults.filter { !blockedUserIds.contains($0.userId ?? "") }) { message in
                MessageRow(
                    message: message,
                    currentUserId: authState.user?.id,
                    showPreviews: showPreviews,
                    digState: digStates[message.id],
                    onReply: { threadMessage = message },
                    onDelete: { messageToDelete = message },
                    onEdit: { messageToEdit = message },
                    onDig: { Task { await toggleDig(for: message) } },
                    onRepost: { messageToRepost = message },
                    onTapAuthor: { username in profileUsername = username },
                    onReport: { reportTarget = .message(id: message.id) },
                    onBlock: { Task { await blockUser(userId: message.userId ?? "", username: message.user?.username ?? "") } }
                )
            }
        }
    }

    private var messageList: some View {
        List {
            Section {
                Toggle("Show previews", isOn: $showPreviews)
                Toggle("My Posts", isOn: $showOnlyMine)
            }
            if !distinctTags.isEmpty {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(distinctTags, id: \.self) { tag in
                                let isActive = tagFilter == tag
                                Button {
                                    tagFilter = isActive ? nil : tag
                                } label: {
                                    Text(tag)
                                        .font(.ilMono())
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(isActive ? ILColor.primary : ILColor.surface2)
                                        .foregroundStyle(isActive ? Color.white : Color.secondary)
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            ForEach(messages.filter { !blockedUserIds.contains($0.userId ?? "") }) { message in
                MessageRow(
                    message: message,
                    currentUserId: authState.user?.id,
                    showPreviews: showPreviews,
                    digState: digStates[message.id],
                    onReply: {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        threadMessage = message
                    },
                    onDelete: {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        messageToDelete = message
                    },
                    onEdit: { messageToEdit = message },
                    onDig: { Task { await toggleDig(for: message) } },
                    onRepost: { messageToRepost = message },
                    onTapAuthor: { username in profileUsername = username },
                    onReport: { reportTarget = .message(id: message.id) },
                    onBlock: { Task { await blockUser(userId: message.userId ?? "", username: message.user?.username ?? "") } }
                )
            }
            if let pagination = pagination, pagination.hasMore, !isLoading {
                HStack {
                    Spacer()
                    ProgressView().frame(width: 24, height: 24)
                    Spacer()
                }
                .onAppear { Task { await loadMore() } }
            }
        }
        .refreshable {
            if showOnlyMine || tagFilter != nil {
                await loadMessages()
            } else {
                syncedFromStore = false
                pagination = nil
                await store.refreshFeed()
            }
        }
    }

    var body: some View {
        navigationContent
            .sheet(item: $threadMessage) { message in
                MessageThreadView(rootMessage: message, currentUserId: authState.user?.id)
                    .environmentObject(authState)
            }
            .sheet(isPresented: Binding(
                get: { profileUsername != nil },
                set: { if !$0 { profileUsername = nil } }
            )) {
                if let username = profileUsername { UserProfileView(username: username) }
            }
            .sheet(isPresented: $showScheduled) { ScheduledMessagesView() }
            .sheet(item: $messageToRepost) { message in
                ComposeView(repostOf: message)
                    .environmentObject(authState)
                    .environmentObject(store)
            }
            .sheet(item: $messageToEdit) { message in
                EditMessageView(message: message) { updated in
                    if let index = messages.firstIndex(where: { $0.id == updated.id }) {
                        messages[index] = updated
                    }
                }
            }
            .alert("Delete message?", isPresented: Binding(
                get: { messageToDelete != nil },
                set: { if !$0 { messageToDelete = nil; deleteError = nil } }
            )) {
                Button("Cancel", role: .cancel) { messageToDelete = nil; deleteError = nil }
                Button("Delete", role: .destructive) {
                    guard let msg = messageToDelete else { return }
                    deleteError = nil
                    Task { await deleteMessage(msg) }
                }
            } message: {
                Text(deleteError ?? "This cannot be undone.")
            }
            .sheet(item: $reportTarget) { target in
                ReportSheet(target: target, onDismiss: { reportTarget = nil })
                    .environmentObject(authState)
            }
    }

    private var navigationContent: some View {
        let nav = NavigationStack {
            feedContent
                .navigationTitle("InterlinedList")
                .navigationBarTitleDisplayMode(.inline)
                .searchable(text: $searchText, prompt: "Search posts")
                .onSubmit(of: .search) { Task { await runSearch() } }
                .onChange(of: searchText) { _, newValue in
                    if newValue.isEmpty {
                        searchResults = []
                        searchPerformed = false
                    }
                }
                .toolbar { feedToolbar }
        }
        .sheet(isPresented: $showCompose) {
            ComposeView()
                .environmentObject(authState)
                .environmentObject(store)
        }
        .task { await applyInitialState() }
        .onChange(of: authState.user?.id) { _, _ in
            if authState.isLoggedIn { Task { await loadMessages() } }
        }
        return nav
            .onChange(of: store.feedMessages.count) { _, _ in
                guard !syncedFromStore && !showOnlyMine && tagFilter == nil else { return }
                let msgs = store.feedMessages
                messages = msgs
                initDigStates(from: msgs)
                isLoading = false
                syncedFromStore = !msgs.isEmpty
            }
            .onChange(of: store.feedLoading) { _, loading in
                guard !showOnlyMine && tagFilter == nil else { return }
                if !loading && messages.isEmpty {
                    messages = store.feedMessages
                    initDigStates(from: messages)
                    isLoading = false
                    syncedFromStore = !messages.isEmpty
                }
            }
            .onChange(of: showOnlyMine) { _, _ in Task { await loadMessages() } }
            .onChange(of: tagFilter) { _, _ in Task { await loadMessages() } }
    }

    @ToolbarContentBuilder
    private var feedToolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            HStack(spacing: 8) {
                Image("Logo").resizable().frame(width: 28, height: 28).clipped()
                Text("InterlinedList").font(.ilTitle()).foregroundStyle(.white)
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            HStack(spacing: 4) {
                // Scheduled posts are a subscriber-only feature; entry point hidden
                // entirely for free users per the iOS-free-app direction.
                if authState.user?.isSubscriber == true {
                    Button { showScheduled = true } label: { Image(systemName: "calendar") }
                        .accessibilityLabel("Scheduled posts")
                }
                Button { showCompose = true } label: { Image(systemName: "square.and.pencil") }
                    .accessibilityLabel("Compose")
            }
        }
    }

    private func applyInitialState() async {
        if !store.feedMessages.isEmpty && messages.isEmpty {
            messages = store.feedMessages
            initDigStates(from: messages)
            isLoading = false
            syncedFromStore = true
        } else {
            isLoading = store.feedLoading
        }
    }

    private func toggleDig(for message: Message) async {
        let current = digStates[message.id]
        let isDug = current?.dugByMe ?? message.dugByMe ?? false
        do {
            let result: APIClient.DigResponse
            if isDug {
                result = try await APIClient.shared.undig(messageId: message.id)
            } else {
                result = try await APIClient.shared.dig(messageId: message.id)
            }
            digStates[message.id] = (count: result.digCount, dugByMe: result.dugByMe)
            locallyToggled.insert(message.id)
        } catch APIError.status(401) {
            authState.handleUnauthorized()
        } catch {
            // Silently ignore dig errors — not critical
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

    private func runSearch() async {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        isSearching = true
        defer { isSearching = false }
        do {
            let (results, _) = try await APIClient.shared.searchMessages(q: q)
            searchResults = results
            searchPerformed = true
            initDigStates(from: results)
        } catch APIError.status(401) {
            authState.handleUnauthorized()
        } catch {
            searchResults = []
            searchPerformed = true
        }
    }

    private func blockUser(userId: String, username: String) async {
        guard !userId.isEmpty else { return }
        blockedUserIds.insert(userId)
        do {
            try await APIClient.shared.blockUser(id: userId)
        } catch APIError.status(401) {
            authState.handleUnauthorized()
            blockedUserIds.remove(userId)
        } catch {
            blockedUserIds.remove(userId)
        }
    }

    private func loadMessages() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            let (list, pag) = try await APIClient.shared.messages(limit: 50, offset: 0, onlyMine: showOnlyMine, tag: tagFilter)
            messages = list
            pagination = pag
            initDigStates(from: list)
        } catch APIError.status(401) {
            authState.handleUnauthorized()
        } catch APIError.server(let message) {
            errorMessage = message
        } catch {
            errorMessage = "Connection failed. Please try again."
        }
    }

    private func loadMore() async {
        syncedFromStore = true
        guard let pag = pagination, pag.hasMore else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let (list, pag) = try await APIClient.shared.messages(limit: 50, offset: messages.count, onlyMine: showOnlyMine, tag: tagFilter)
            messages.append(contentsOf: list)
            pagination = pag
            initDigStates(from: list)
        } catch {
            errorMessage = "Failed to load more."
        }
    }

    private func initDigStates(from list: [Message]) {
        for message in list {
            guard !locallyToggled.contains(message.id) else { continue }
            digStates[message.id] = (count: message.digCount ?? 0, dugByMe: message.dugByMe ?? false)
        }
    }
}

struct MessageRow: View {
    let message: Message
    let currentUserId: String?
    let showPreviews: Bool
    let digState: (count: Int, dugByMe: Bool)?
    let onReply: () -> Void
    let onDelete: () -> Void
    let onEdit: () -> Void
    let onDig: () -> Void
    var onRepost: (() -> Void)? = nil
    var onTapAuthor: ((String) -> Void)? = nil
    var onReport: (() -> Void)? = nil
    var onBlock: (() -> Void)? = nil

    private var canDelete: Bool {
        guard let uid = currentUserId else { return false }
        return message.userId == uid
    }

    private var isPrivate: Bool {
        message.publiclyVisible == false
    }

    private var effectiveDigCount: Int {
        digState?.count ?? message.digCount ?? 0
    }

    private var effectiveDugByMe: Bool {
        digState?.dugByMe ?? message.dugByMe ?? false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if let onTapAuthor, let username = message.user?.username {
                    Button {
                        onTapAuthor(username)
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
                }
                Spacer()
                Text(formatDate(message.createdAt))
                    .font(.ilMono())
                    .foregroundStyle(.secondary)
            }
            Text(message.content)
                .font(.ilBody())
            if let tags = message.tags, !tags.isEmpty {
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
            if showPreviews && message.hasPreviews {
                previewSection
            }
            HStack(spacing: 12) {
                Button {
                    onReply()
                } label: {
                    Label("Reply", systemImage: "arrowshape.turn.up.left")
                        .font(.ilMono())
                }
                .buttonStyle(.borderless)
                Button {
                    onDig()
                } label: {
                    Label(effectiveDugByMe ? "Dug" : "Dig", systemImage: effectiveDugByMe ? "hand.thumbsup.fill" : "hand.thumbsup")
                        .font(.ilMono())
                }
                .buttonStyle(.borderless)
                if effectiveDigCount > 0 {
                    Text("\(effectiveDigCount)")
                        .font(.ilMono())
                        .foregroundStyle(.secondary)
                }
                if let onRepost {
                    Button {
                        onRepost()
                    } label: {
                        Label("Repost", systemImage: "arrow.2.squarepath")
                            .font(.ilMono())
                    }
                    .buttonStyle(.borderless)
                }
                if canDelete {
                    Button {
                        onEdit()
                    } label: {
                        Label("Edit", systemImage: "pencil")
                            .font(.ilMono())
                    }
                    .buttonStyle(.borderless)
                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Label("Delete", systemImage: "trash")
                            .font(.ilMono())
                    }
                    .buttonStyle(.borderless)
                } else if onReport != nil || onBlock != nil {
                    Menu {
                        if let onReport {
                            Button(role: .destructive) {
                                onReport()
                            } label: {
                                Label("Report…", systemImage: "flag")
                            }
                        }
                        if let onBlock {
                            Button(role: .destructive) {
                                onBlock()
                            } label: {
                                Label("Block user", systemImage: "person.slash")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.ilMono())
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("More options")
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
        .padding(.top, 4)
    }

    private func formatDate(_ iso: String) -> String {
        if let date = isoFullFormatter.date(from: iso) ?? isoBasicFormatter.date(from: iso) {
            return relativeDateFormatter.localizedString(for: date, relativeTo: Date())
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
                    .font(.ilBody(15))
                    .fontWeight(.medium)
                    .lineLimit(2)
            }
            if let desc = meta.description, !desc.isEmpty {
                Text(desc)
                    .font(.ilMono())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(8)
        .background(ILColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// Shared across all MessageRow and LinkPreviewBlock instances — allocated once,
// reused per render. ISO8601DateFormatter and RelativeDateTimeFormatter are
// expensive to construct; creating them per-cell causes scroll jitter.
private let isoFullFormatter: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()
private let isoBasicFormatter = ISO8601DateFormatter()
private let relativeDateFormatter: RelativeDateTimeFormatter = {
    let f = RelativeDateTimeFormatter()
    f.unitsStyle = .abbreviated
    return f
}()
