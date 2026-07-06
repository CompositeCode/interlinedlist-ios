//
//  UserProfileView.swift
//  InterlinedList
//

import SwiftUI
import UIKit

struct UserProfileView: View {
    let username: String

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var authState: AuthState
    @State private var selectedTab = 0
    @State private var messages: [Message] = []
    @State private var lists: [UserList] = []
    @State private var isLoadingMessages = true
    @State private var isLoadingLists = false
    @State private var messagesError: String?
    @State private var listsError: String?
    @State private var pagination: Pagination?
    @State private var targetUserId: String?
    @State private var followStatus: FollowStatus?
    @State private var followCounts: FollowCounts?
    @State private var mutualCounts: MutualCounts?
    @State private var isFollowLoading = false
    @State private var followError: String?
    @State private var isExporting: ExportType? = nil
    @State private var exportedData: Data? = nil
    @State private var exportFilename: String = "export.csv"
    @State private var showShareSheet = false
    @State private var exportError: String? = nil
    @State private var organizations: [Organization] = []
    @State private var organizationsLoaded = false
    @State private var documents: [PublicDocumentSummary] = []
    @State private var isLoadingDocuments = false
    @State private var documentsError: String?
    @State private var documentsLoaded = false
    @State private var showReportSheet = false
    @State private var isBlocked = false
    @State private var blockError: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if authState.user?.username != username {
                    followHeader
                }

                Picker("Content", selection: $selectedTab) {
                    Text("Posts").tag(0)
                    Text("Lists").tag(1)
                    Text("Documents").tag(2)
                }
                .pickerStyle(.segmented)
                .padding()

                switch selectedTab {
                case 0: messagesTab
                case 1: listsTab
                default: documentsTab
                }

                if authState.user?.username == username {
                    organizationsSection
                    exportSection
                }
            }
            .navigationTitle("@\(username)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                if authState.user?.username != username {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button(role: .destructive) {
                                showReportSheet = true
                            } label: {
                                Label("Report @\(username)…", systemImage: "flag")
                            }
                            Button(role: .destructive) {
                                Task { await toggleBlock() }
                            } label: {
                                Label(isBlocked ? "Unblock @\(username)" : "Block @\(username)", systemImage: "person.slash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .accessibilityLabel("More options")
                    }
                }
            }
            .sheet(isPresented: $showReportSheet) {
                if let uid = targetUserId {
                    ReportSheet(target: .user(id: uid, username: username), onDismiss: { showReportSheet = false })
                        .environmentObject(authState)
                }
            }
            .task {
                await loadMessages()
                if authState.user?.username == username && !organizationsLoaded {
                    await loadOrganizations()
                }
            }
            .onChange(of: selectedTab) { _, tab in
                if tab == 1 && lists.isEmpty && listsError == nil {
                    Task { await loadLists() }
                } else if tab == 2 && !documentsLoaded {
                    Task { await loadDocuments() }
                }
            }
            .sheet(isPresented: $showShareSheet) {
                if let data = exportedData {
                    ShareSheet(data: data, filename: exportFilename)
                }
            }
        }
    }

    @ViewBuilder
    private var followHeader: some View {
        VStack(spacing: 8) {
            HStack(spacing: 24) {
                if let counts = followCounts, let uid = targetUserId {
                    NavigationLink {
                        FollowListView(userId: uid, mode: .followers)
                            .environmentObject(authState)
                    } label: {
                        countView(value: counts.followers, label: "Followers")
                    }
                    .buttonStyle(.plain)
                    NavigationLink {
                        FollowListView(userId: uid, mode: .following)
                            .environmentObject(authState)
                    } label: {
                        countView(value: counts.following, label: "Following")
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                if targetUserId != nil {
                    followButton
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)

            if let mutual = mutualCounts, mutual.mutualFollowers > 0 || mutual.mutualFollowing > 0 {
                Text(mutualSummary(mutual))
                    .font(.ilMono())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
            }

            if let error = followError {
                Text(error)
                    .font(.ilMono())
                    .foregroundStyle(.red)
                    .padding(.horizontal)
            }
        }
        Divider()
    }

    private func countView(value: Int, label: String) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.ilTitle())
                .foregroundStyle(.primary)
            Text(label)
                .font(.ilMono())
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(label)")
        .accessibilityHint("Shows the full list")
    }

    private func mutualSummary(_ m: MutualCounts) -> String {
        var parts: [String] = []
        if m.mutualFollowers > 0 { parts.append("\(m.mutualFollowers) mutual follower\(m.mutualFollowers == 1 ? "" : "s")") }
        if m.mutualFollowing > 0 { parts.append("\(m.mutualFollowing) followed in common") }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var followButton: some View {
        if isFollowLoading {
            ProgressView()
                .frame(width: 80, height: 32)
        } else if followStatus?.pendingRequest == true {
            Button("Requested") { Task { await toggleFollow() } }
                .buttonStyle(.bordered)
                .controlSize(.small)
        } else if followStatus?.following == true {
            Button("Following") { Task { await toggleFollow() } }
                .buttonStyle(.bordered)
                .controlSize(.small)
        } else {
            Button("Follow") { Task { await toggleFollow() } }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
    }

    @ViewBuilder
    private var messagesTab: some View {
        if isLoadingMessages && messages.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = messagesError, messages.isEmpty {
            ContentUnavailableView {
                Label("Unable to load", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            } actions: {
                Button("Retry") { Task { await loadMessages() } }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if messages.isEmpty {
            ContentUnavailableView {
                Label("No Posts", systemImage: "text.bubble")
            } description: {
                Text("@\(username) has no public posts.")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(messages) { message in
                    PublicMessageRow(message: message)
                }
                if let pag = pagination, pag.hasMore, !isLoadingMessages {
                    HStack { Spacer(); ProgressView(); Spacer() }
                        .onAppear { Task { await loadMoreMessages() } }
                }
            }
            .refreshable { await loadMessages() }
        }
    }

    @ViewBuilder
    private var listsTab: some View {
        if isLoadingLists {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = listsError {
            ContentUnavailableView {
                Label("Unable to load", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            } actions: {
                Button("Retry") { Task { await loadLists() } }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if lists.isEmpty {
            ContentUnavailableView {
                Label("No Lists", systemImage: "list.bullet.rectangle")
            } description: {
                Text("@\(username) has no public lists.")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(lists) { list in
                NavigationLink {
                    PublicListDetailView(username: username, listId: list.id, listTitle: list.name)
                        .environmentObject(authState)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(list.name)
                            .font(.ilBody())
                        if let desc = list.description, !desc.isEmpty {
                            Text(desc)
                                .font(.ilMono())
                                .foregroundStyle(.secondary)
                        }
                        if let count = list.itemCount {
                            Text("\(count) items")
                                .font(.ilMono(10))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            .refreshable { await loadLists() }
        }
    }

    @ViewBuilder
    private var documentsTab: some View {
        if isLoadingDocuments && documents.isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = documentsError {
            ContentUnavailableView {
                Label("Unable to load", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            } actions: {
                Button("Retry") { Task { await loadDocuments() } }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if documents.isEmpty {
            ContentUnavailableView {
                Label("No Documents", systemImage: "doc.text")
            } description: {
                Text("@\(username) has no public documents.")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(documents) { doc in
                NavigationLink {
                    PublicDocumentReader(documentId: doc.id, title: doc.title)
                        .environmentObject(authState)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(doc.title).font(.ilBody())
                        if let path = doc.relativePath, !path.isEmpty {
                            Text(path).font(.ilMono()).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .refreshable { await loadDocuments() }
        }
    }

    private func loadMessages() async {
        messagesError = nil
        isLoadingMessages = true
        defer { isLoadingMessages = false }
        do {
            let (msgs, pag) = try await APIClient.shared.publicMessages(username: username)
            messages = msgs
            pagination = pag
            if targetUserId == nil {
                targetUserId = messages.first?.userId
                if let userId = targetUserId, userId != authState.user?.id {
                    Task { await loadFollowInfo(userId: userId) }
                }
            }
        } catch {
            messagesError = "Could not load posts."
        }
    }

    private func loadMoreMessages() async {
        guard let pag = pagination, pag.hasMore else { return }
        isLoadingMessages = true
        defer { isLoadingMessages = false }
        do {
            let (more, pag) = try await APIClient.shared.publicMessages(username: username, limit: 50, offset: messages.count)
            messages.append(contentsOf: more)
            pagination = pag
        } catch {}
    }

    private func loadLists() async {
        listsError = nil
        isLoadingLists = true
        defer { isLoadingLists = false }
        do {
            lists = try await APIClient.shared.publicLists(username: username)
        } catch {
            listsError = "Could not load lists."
        }
    }

    private func loadDocuments() async {
        documentsError = nil
        isLoadingDocuments = true
        documentsLoaded = true
        defer { isLoadingDocuments = false }
        do {
            documents = try await APIClient.shared.publicDocuments(username: username).documents
        } catch {
            documentsError = "Could not load documents."
        }
    }

    private func loadFollowInfo(userId: String) async {
        do {
            async let statusTask = APIClient.shared.followStatus(userId: userId)
            async let countsTask = APIClient.shared.followCounts(userId: userId)
            let (status, counts) = try await (statusTask, countsTask)
            followStatus = status
            followCounts = counts
        } catch {
            // Follow info is supplementary — silently ignore errors
        }
        // Mutual counts are a separate, best-effort call.
        mutualCounts = try? await APIClient.shared.mutualCounts(userId: userId)
    }

    @ViewBuilder
    private var organizationsSection: some View {
        if !organizations.isEmpty {
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                Text("Organizations")
                    .font(.ilBody(11))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.top, 16)
                    .padding(.bottom, 8)
                ForEach(organizations) { org in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(org.name)
                            .font(.ilBody())
                        if let desc = org.description, !desc.isEmpty {
                            Text(desc)
                                .font(.ilMono())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(accessibilityLabel(for: org))
                }
            }
        }
    }

    private func accessibilityLabel(for org: Organization) -> String {
        if let desc = org.description, !desc.isEmpty {
            return "\(org.name). \(desc)"
        }
        return org.name
    }

    private func loadOrganizations() async {
        organizationsLoaded = true
        do {
            organizations = try await APIClient.shared.userOrganizations()
        } catch {
            organizations = []
        }
    }

    @ViewBuilder
    private var exportSection: some View {
        Divider()
        VStack(alignment: .leading, spacing: 0) {
            Text("Export Your Data")
                .font(.ilBody(11))
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.top, 16)
                .padding(.bottom, 8)
            exportButton(label: "Messages", type: .messages)
            exportButton(label: "Lists", type: .lists)
            exportButton(label: "Follows", type: .follows)
            if let err = exportError {
                Text(err)
                    .foregroundStyle(.red)
                    .font(.ilMono())
                    .padding(.horizontal)
                    .padding(.top, 4)
            }
        }
        .padding(.bottom, 16)
    }

    @ViewBuilder
    private func exportButton(label: String, type: ExportType) -> some View {
        Button {
            Task { await export(type) }
        } label: {
            HStack {
                if isExporting == type {
                    ProgressView().frame(width: 20, height: 20)
                }
                Text("Export \(label) (CSV)")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "square.and.arrow.up")
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
        .disabled(isExporting != nil)
        .accessibilityLabel("Export \(label) as CSV")
    }

    private func export(_ type: ExportType) async {
        exportError = nil
        isExporting = type
        defer { isExporting = nil }
        do {
            let data = try await APIClient.shared.exportCSV(type)
            exportedData = data
            exportFilename = "\(type.rawValue)-export.csv"
            showShareSheet = true
        } catch APIError.status(401) {
            authState.handleUnauthorized()
        } catch APIError.server(let msg) {
            exportError = msg
        } catch {
            exportError = "Export failed. Please try again."
        }
    }

    private func toggleFollow() async {
        guard let userId = targetUserId else { return }
        isFollowLoading = true
        defer { isFollowLoading = false }
        followError = nil
        do {
            if followStatus?.following == true {
                try await APIClient.shared.unfollowUser(userId: userId)
                followStatus = FollowStatus(following: false, followedBy: followStatus?.followedBy ?? false, pendingRequest: false)
                followCounts = followCounts.map { FollowCounts(followers: max(0, $0.followers - 1), following: $0.following) }
            } else {
                let updated = try await APIClient.shared.followUser(userId: userId)
                followStatus = updated
                if updated.following {
                    followCounts = followCounts.map { FollowCounts(followers: $0.followers + 1, following: $0.following) }
                }
            }
        } catch APIError.status(401) {
            authState.handleUnauthorized()
        } catch APIError.server(let msg) {
            followError = msg
        } catch {
            followError = "Action failed. Please try again."
        }
    }

    private func toggleBlock() async {
        guard let uid = targetUserId else { return }
        blockError = nil
        do {
            if isBlocked {
                try await APIClient.shared.unblockUser(id: uid)
                isBlocked = false
            } else {
                try await APIClient.shared.blockUser(id: uid)
                isBlocked = true
            }
        } catch APIError.status(401) {
            authState.handleUnauthorized()
        } catch {
            blockError = isBlocked ? "Could not unblock user." : "Could not block user."
        }
    }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let data: Data
    let filename: String

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try? data.write(to: url)
        return UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private struct PublicMessageRow: View {
    let message: Message

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(message.authorDisplay)
                    .font(.ilBody(15))
                    .fontWeight(.medium)
                Spacer()
                Text(formatDate(message.createdAt))
                    .font(.ilMono())
                    .foregroundStyle(.secondary)
            }
            Text(message.content)
                .font(.ilBody())
            if let tags = message.tags, !tags.isEmpty {
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
        .padding(.vertical, 4)
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
    UserProfileView(username: "testuser")
        .environmentObject(AuthState())
}
