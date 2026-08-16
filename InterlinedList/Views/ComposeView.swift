//
//  ComposeView.swift
//  InterlinedList
//

import SwiftUI
import PhotosUI
import OSLog

private let composeLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "InterlinedList", category: "ComposeView")

/// Fallback when user's maxMessageLength is not available (matches API default).
private let defaultMaxMessageLength = 666

struct ComposeView: View {
    @EnvironmentObject var authState: AuthState
    @EnvironmentObject var store: AppDataStore
    @Environment(\.dismiss) private var dismiss
    /// When set, this view posts a reply to the given message.
    var replyTo: Message? = nil
    /// When set, this view reposts (pushes) the given message, with optional commentary.
    var repostOf: Message? = nil
    @State private var content = ""
    @State private var tags = ""
    @State private var linkPreview: LinkMetadataItem?
    @State private var publiclyVisible = true
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showSuccess = false
    @State private var showAdvancedBar = false
    @StateObject private var imageUploader = ComposeImageUploader()
    @State private var photoSelection: [PhotosPickerItem] = []
    @State private var selectedVideo: PhotosPickerItem?
    @State private var uploadedVideoURL: String?
    @State private var isUploadingVideo = false
    @State private var scheduledDate: Date?
    @State private var showSchedulePicker = false
    // Cross-posting (subscriber-only)
    @State private var crossPostBluesky = false
    @State private var crossPostLinkedIn = false
    @State private var crossPostTwitter = false
    @State private var allIdentities: [APIClient.LinkedIdentity] = []
    @State private var selectedMastodonIds: Set<String> = []
    @State private var identitiesLoaded = false
    // LinkedIn posting-target picker (subscriber + LinkedIn identity only)
    @State private var linkedInTargets: [LinkedInPostingTarget] = []
    @State private var selectedLinkedInTargetIds: Set<String> = []
    @State private var linkedInTargetsLoaded = false
    @State private var linkedInLinkAsFirstComment = false
    @State private var lastCrossPostResults: [CrossPostResult] = []
    /// Destinations the server reported the message actually reached (`crossPostUrls`).
    /// Used for the post-publish confirmation when the deployment doesn't return the
    /// per-platform `crossPostResults` shape (which, in practice, it usually doesn't).
    @State private var lastCrossPostUrls: [CrossPostUrl] = []
    @State private var postableOrgs: [Organization] = []
    @State private var selectedOrgId: String? = nil

    private var isReply: Bool { replyTo != nil }
    private var isRepost: Bool { repostOf != nil }

    /// Subscriber-only compose features (image / video upload, cross-posting,
    /// scheduling) are hidden entirely for non-subscribers per the iOS-free-app
    /// direction. No paywall, no disabled-but-tappable controls — the UI
    /// simply does not surface them.
    private var canUseSubscriberFeatures: Bool {
        authState.user?.isSubscriber == true
    }

    /// Free users with unverified email cannot post (matches site behavior).
    /// User is missing while view is initializing; treat that as verified so the
    /// button isn't disabled in the brief window before authState lands.
    private var isEmailVerified: Bool {
        authState.user.map { $0.emailVerified != false } ?? true
    }

    /// Image/video upload is subscriber-gated *and* requires a verified email
    /// server-side. Hide the pickers when unverified so the user doesn't start an
    /// upload that 403s (the post button already blocks posting when unverified).
    private var canAttachMedia: Bool {
        canUseSubscriberFeatures && isEmailVerified
    }

    /// Apply user's default settings for public visibility and advanced bar. Call when view appears (new post) or after successful post.
    private func applyUserDefaults() {
        guard !isReply else { return }
        publiclyVisible = authState.user?.defaultPubliclyVisible ?? true
        showAdvancedBar = authState.user?.showAdvancedPostSettings ?? false
    }
    private var maxMessageLength: Int { authState.user?.maxMessageLength ?? defaultMaxMessageLength }
    private var remainingCharacters: Int { max(0, maxMessageLength - content.count) }

    var body: some View {
        NavigationStack {
            Form {
                if let original = repostOf {
                    Section {
                        repostPreview(original)
                    }
                }
                Section {
                    TextField(composePlaceholder, text: $content, axis: .vertical)
                        .lineLimit(5...15)
                    if !isReply {
                        TextField("Tags (comma-separated)", text: $tags)
                            .font(.ilBody(15))
                            .foregroundStyle(.secondary)
                    }
                    if !isReply {
                        advancedToolbar
                        Toggle("Public", isOn: $publiclyVisible)
                    }
                    if showSchedulePicker && !isReply && canUseSubscriberFeatures {
                        schedulePicker
                    }
                    if !imageUploader.attachments.isEmpty {
                        ComposeImageStrip(uploader: imageUploader)
                    }
                    if let url = uploadedVideoURL {
                        uploadedVideoPreview(url: url)
                    }
                }

                if let preview = linkPreview,
                   preview.fetchStatus == "success",
                   let meta = preview.metadata {
                    Section {
                        LinkPreviewBlock(link: preview, meta: meta)
                            .accessibilityLabel("Link preview: \(meta.title ?? preview.url)")
                    } header: {
                        Text("Link preview")
                    }
                }

                if !isReply && !isRepost && !postableOrgs.isEmpty {
                    Section("Post Message As") {
                        Picker("Author", selection: $selectedOrgId) {
                            Text("Yourself").tag(String?.none)
                            ForEach(postableOrgs) { org in
                                Text(org.name).tag(Optional(org.id))
                            }
                        }
                        .accessibilityLabel("Post author")
                    }
                }

                if showAdvancedBar && !isReply && canUseSubscriberFeatures {
                    crossPostSection
                }

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.ilMono())
                    }
                }

                Section {
                    Button {
                        Task { await postMessage() }
                    } label: {
                        HStack {
                            if isLoading {
                                ProgressView()
                                    .frame(width: 20, height: 20)
                            }
                            Text(postButtonLabel)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(isLoading || !canSubmit || !isEmailVerified)
                } footer: {
                    if !isEmailVerified {
                        Text("Verify your email to enable posting.")
                            .font(.ilMono())
                            .foregroundStyle(ILColor.amber)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(navTitle)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                applyUserDefaults()
            }
            .task {
                await loadIdentitiesIfNeeded()
                await loadPostableOrgs()
            }
            .alert(successTitle, isPresented: $showSuccess) {
                Button("OK") {
                    content = ""
                    linkPreview = nil
                    imageUploader.reset()
                    photoSelection = []
                    uploadedVideoURL = nil
                    selectedVideo = nil
                    scheduledDate = nil
                    showSchedulePicker = false
                    lastCrossPostResults = []
                    lastCrossPostUrls = []
                    crossPostBluesky = false
                    crossPostLinkedIn = false
                    crossPostTwitter = false
                    selectedMastodonIds = []
                    selectedLinkedInTargetIds = Set(enabledLinkedInTargets.map { $0.id })
                    linkedInLinkAsFirstComment = false
                    selectedOrgId = nil
                    applyUserDefaults()
                }
            } message: {
                Text(successMessage)
            }
            .onChange(of: photoSelection) { _, items in
                guard !items.isEmpty else { return }
                let picked = items
                photoSelection = []
                Task { await imageUploader.add(picked) }
            }
            .onChange(of: crossPostLinkedIn) { _, isOn in
                guard isOn else { return }
                Task { await loadLinkedInTargetsIfNeeded() }
            }
            .task(id: firstDetectedURL) {
                guard let url = firstDetectedURL else {
                    linkPreview = nil
                    return
                }
                // Debounce keystrokes; the endpoint is rate-limited (30/60s).
                try? await Task.sleep(nanoseconds: 400_000_000)
                guard !Task.isCancelled else { return }
                await loadLinkPreview(url)
            }
        }
    }

    // MARK: - Link preview (G14)

    /// The first `http(s)` URL in the draft, used to drive a live preview card.
    /// Recomputed on each content change; cheap enough for per-keystroke use.
    private var firstDetectedURL: String? {
        guard !content.isEmpty,
              let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        else { return nil }
        let range = NSRange(content.startIndex..<content.endIndex, in: content)
        guard let match = detector.firstMatch(in: content, options: [], range: range),
              let url = match.url,
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else { return nil }
        return url.absoluteString
    }

    private func loadLinkPreview(_ url: String) async {
        do {
            let item = try await APIClient.shared.linkMetadata(url: url)
            guard !Task.isCancelled else { return }
            linkPreview = item
        } catch {
            // Rate-limited (429), fetch failure, or offline → show no card rather
            // than surfacing an error; the preview is a non-essential nicety.
            linkPreview = nil
        }
    }

    // MARK: - Derived strings

    private var composePlaceholder: String {
        if isReply { return "Write a reply…" }
        if isRepost { return "Add a comment (optional)…" }
        return "What's on your mind?"
    }

    private var navTitle: String {
        if isReply { return "Reply" }
        if isRepost { return "Repost" }
        return "New Message"
    }

    private var postButtonLabel: String {
        if isRepost { return "Repost" }
        if scheduledDate != nil { return "Schedule" }
        return isReply ? "Reply" : "Post Message"
    }

    /// Reposts may have empty commentary; everything else requires content.
    private var canSubmit: Bool {
        guard !imageUploader.isUploading else { return false }
        if isRepost { return true }
        if !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        return !imageUploader.uploadedURLs.isEmpty
    }

    private var successTitle: String {
        if isReply { return "Replied" }
        if isRepost { return "Reposted" }
        return scheduledDate != nil ? "Scheduled" : "Message Posted"
    }

    private var successMessage: String {
        let base: String
        if isReply { base = "Your reply was posted." }
        else if isRepost { base = "You reposted this." }
        else if scheduledDate != nil { base = "Your message has been scheduled." }
        else { base = "Your message was posted." }
        if let summary = CrossPostSummary.line(urls: lastCrossPostUrls, results: lastCrossPostResults) {
            return base + "\n" + summary
        }
        return base
    }

    @ViewBuilder
    private var attachPhotosButton: some View {
        let attached = imageUploader.count
        PhotosPicker(
            selection: $photoSelection,
            maxSelectionCount: max(1, imageUploader.remainingSlots),
            selectionBehavior: .ordered,
            matching: .images
        ) {
            HStack(spacing: 4) {
                Image(systemName: attached > 0 ? "photo.fill.on.rectangle.fill" : "photo")
                    .font(.ilBody())
                    .foregroundStyle(attached > 0 ? ILColor.primary : Color.secondary)
                if attached > 0 {
                    Text("\(attached)/\(ComposeImageUploader.maxImages)")
                        .font(.ilMono())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.borderless)
        .disabled(imageUploader.remainingSlots == 0)
        .accessibilityLabel("Attach photos")
    }

    @ViewBuilder
    private var advancedToolbar: some View {
        HStack(alignment: .center, spacing: 8) {
            Text("\(remainingCharacters) characters remaining")
                .font(.ilMono())
                .foregroundStyle(.secondary)
            if canUseSubscriberFeatures {
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        showAdvancedBar.toggle()
                    }
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.ilBody())
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(showAdvancedBar ? 90 : 0))
                }
                .buttonStyle(.borderless)
            }
            if showAdvancedBar && canUseSubscriberFeatures {
                HStack(spacing: 12) {
                    if canAttachMedia {
                        attachPhotosButton
                        PhotosPicker(selection: $selectedVideo, matching: .videos) {
                            if isUploadingVideo {
                                ProgressView()
                                    .frame(width: 20, height: 20)
                            } else {
                                Image(systemName: uploadedVideoURL != nil ? "video.fill" : "video")
                                    .font(.ilBody())
                                    .foregroundStyle(uploadedVideoURL != nil ? ILColor.primary : Color.secondary)
                            }
                        }
                        .buttonStyle(.borderless)
                        .disabled(isUploadingVideo)
                        .accessibilityLabel("Attach video")
                        .onChange(of: selectedVideo) { _, newItem in
                            guard let newItem else { return }
                            Task { await uploadVideo(newItem) }
                        }
                    }
                    Button {
                        withAnimation {
                            showSchedulePicker.toggle()
                            if !showSchedulePicker { scheduledDate = nil }
                        }
                    } label: {
                        Image(systemName: scheduledDate != nil ? "calendar.badge.clock" : "calendar")
                            .font(.ilBody())
                            .foregroundStyle(scheduledDate != nil ? ILColor.primary : Color.secondary)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(scheduledDate != nil ? "Clear schedule" : "Schedule message")
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var schedulePicker: some View {
        DatePicker(
            "Send at",
            selection: Binding(
                get: { scheduledDate ?? Date().addingTimeInterval(3600) },
                set: { scheduledDate = $0 }
            ),
            in: Date()...,
            displayedComponents: [.date, .hourAndMinute]
        )
        .onAppear {
            if scheduledDate == nil {
                scheduledDate = Date().addingTimeInterval(3600)
            }
        }
        Button("Clear schedule") {
            scheduledDate = nil
            showSchedulePicker = false
        }
        .font(.ilMono())
        .foregroundStyle(.red)
        .buttonStyle(.borderless)
    }

    @ViewBuilder
    private func uploadedVideoPreview(url: String) -> some View {
        HStack {
            Image(systemName: "video.fill")
                .foregroundStyle(.secondary)
            Text("Video attached")
                .font(.ilMono())
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                uploadedVideoURL = nil
                selectedVideo = nil
            } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Remove attached video")
        }
    }

    // MARK: - Cross-post controls

    private var mastodonIdentities: [APIClient.LinkedIdentity] { allIdentities.filter { $0.providerType == "mastodon" } }
    private var hasBluesky: Bool { allIdentities.contains { $0.providerType == "bluesky" } }
    private var hasLinkedIn: Bool { allIdentities.contains { $0.providerType == "linkedin" } }
    private var hasTwitter: Bool { allIdentities.contains { $0.providerType == "twitter" } }
    private var hasMastodon: Bool { !mastodonIdentities.isEmpty }
    private var hasCrossPostTargets: Bool { hasBluesky || hasLinkedIn || hasTwitter || hasMastodon }

    @ViewBuilder
    private var crossPostSection: some View {
        Section {
            if identitiesLoaded && !hasCrossPostTargets {
                Text("Connect social accounts at interlinedlist.com to cross-post.")
                    .font(.ilMono())
                    .foregroundStyle(.secondary)
            }
            if hasBluesky {
                Toggle(isOn: $crossPostBluesky) {
                    Label("Bluesky", systemImage: "cloud")
                }
            }
            if hasLinkedIn {
                Toggle(isOn: $crossPostLinkedIn) {
                    Label("LinkedIn", systemImage: "briefcase")
                }
                if crossPostLinkedIn {
                    linkedInTargetPicker
                }
            }
            if hasTwitter {
                Toggle(isOn: $crossPostTwitter) {
                    Label("X", systemImage: "xmark")
                }
            }
            if hasMastodon {
                Menu {
                    ForEach(mastodonIdentities) { identity in
                        Button {
                            toggleMastodon(identity.id)
                        } label: {
                            if selectedMastodonIds.contains(identity.id) {
                                Label(mastodonLabel(identity), systemImage: "checkmark")
                            } else {
                                Text(mastodonLabel(identity))
                            }
                        }
                    }
                } label: {
                    HStack {
                        Label("Mastodon", systemImage: "number")
                        Spacer()
                        Text(selectedMastodonIds.isEmpty ? "Off" : "\(selectedMastodonIds.count) selected")
                            .font(.ilMono())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("Cross-post")
        } footer: {
            if hasCrossPostTargets {
                Text("Cross-posts are sent when this message publishes.")
                    .font(.ilMono())
            }
        }
    }

    /// Enabled targets are the only ones the user can post to; disabled options are
    /// hidden entirely (they were turned off in the user's web preferences).
    private var enabledLinkedInTargets: [LinkedInPostingTarget] {
        linkedInTargets.filter { $0.enabled }
    }

    @ViewBuilder
    private var linkedInTargetPicker: some View {
        if !enabledLinkedInTargets.isEmpty {
            ForEach(enabledLinkedInTargets) { target in
                Button {
                    toggleLinkedInTarget(target.id)
                } label: {
                    HStack(spacing: 10) {
                        linkedInAvatar(target.avatarUrl)
                        Text(target.label)
                            .font(.ilBody(15))
                            .foregroundStyle(.primary)
                        Spacer()
                        if selectedLinkedInTargetIds.contains(target.id) {
                            Image(systemName: "checkmark")
                                .foregroundStyle(ILColor.primary)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(target.label)\(selectedLinkedInTargetIds.contains(target.id) ? ", selected" : "")")
            }
            Toggle(isOn: $linkedInLinkAsFirstComment) {
                Text("Post link as first comment")
                    .font(.ilBody(15))
            }
            .accessibilityLabel("Post link as first comment on LinkedIn")
        } else if linkedInTargetsLoaded {
            Text("Posting to your personal LinkedIn profile.")
                .font(.ilMono())
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func linkedInAvatar(_ url: String?) -> some View {
        if let url, let parsed = URL(string: url) {
            AsyncImage(url: parsed) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Image(systemName: "person.crop.circle.fill").foregroundStyle(.secondary)
            }
            .frame(width: 24, height: 24)
            .clipShape(Circle())
        } else {
            Image(systemName: "briefcase.circle.fill")
                .resizable()
                .frame(width: 24, height: 24)
                .foregroundStyle(.secondary)
        }
    }

    private func toggleLinkedInTarget(_ id: String) {
        if selectedLinkedInTargetIds.contains(id) {
            selectedLinkedInTargetIds.remove(id)
        } else {
            selectedLinkedInTargetIds.insert(id)
        }
    }

    /// Selected posting union to send in the body. Falls back to personal when
    /// nothing is selected (matches web's post-to-personal-by-default behavior).
    private var resolvedLinkedInTargets: [LinkedInTarget] {
        let selected = enabledLinkedInTargets.filter { selectedLinkedInTargetIds.contains($0.id) }
        if selected.isEmpty { return [.personal()] }
        return selected.map { $0.asTarget }
    }

    private func loadLinkedInTargetsIfNeeded() async {
        guard !linkedInTargetsLoaded, canUseSubscriberFeatures, !isReply, hasLinkedIn else { return }
        linkedInTargetsLoaded = true
        do {
            linkedInTargets = try await APIClient.shared.linkedInPostingTargets()
            selectedLinkedInTargetIds = Set(enabledLinkedInTargets.map { $0.id })
        } catch {
            // Never block posting — fall back to personal-only at post time.
            composeLog.error("linkedInPostingTargets failed: \(error)")
            linkedInTargets = []
        }
    }

    private func mastodonLabel(_ identity: APIClient.LinkedIdentity) -> String {
        identity.providerUsername ?? "Mastodon account"
    }

    private func toggleMastodon(_ id: String) {
        if selectedMastodonIds.contains(id) {
            selectedMastodonIds.remove(id)
        } else {
            selectedMastodonIds.insert(id)
        }
    }

    private func loadIdentitiesIfNeeded() async {
        guard !identitiesLoaded, canUseSubscriberFeatures, !isReply else { return }
        identitiesLoaded = true
        do {
            allIdentities = try await APIClient.shared.linkedIdentities()
        } catch {
            allIdentities = []
        }
    }

    private func loadPostableOrgs() async {
        guard !isReply && !isRepost else { return }
        let orgs = (try? await APIClient.shared.userOrganizations()) ?? []
        postableOrgs = orgs.filter { org in
            guard let role = org.role else { return false }
            return role == .owner || role == .admin
        }
    }

    @ViewBuilder
    private func repostPreview(_ original: Message) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.2.squarepath")
                    .font(.ilMono(10))
                    .foregroundStyle(.secondary)
                Text(original.authorDisplay)
                    .font(.ilMono())
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
            }
            Text(original.content)
                .font(.ilBody(15))
                .lineLimit(4)
                .foregroundStyle(.primary)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Reposting \(original.authorDisplay): \(original.content)")
    }

    private func uploadVideo(_ item: PhotosPickerItem) async {
        isUploadingVideo = true
        errorMessage = nil
        defer { isUploadingVideo = false }
        do {
            let videoData: Data
            let mimeType: String
            if let fileURL = try await item.loadTransferable(type: URL.self) {
                videoData = try Data(contentsOf: fileURL)
                let ext = fileURL.pathExtension.lowercased()
                mimeType = ext == "mp4" ? "video/mp4" : "video/quicktime"
            } else if let data = try await item.loadTransferable(type: Data.self) {
                videoData = data
                mimeType = item.supportedContentTypes.first?.preferredMIMEType ?? "video/mp4"
            } else {
                composeLog.error("uploadVideo: both URL and Data transferable returned nil")
                errorMessage = "Could not load video from photo library."
                selectedVideo = nil
                return
            }
            uploadedVideoURL = try await APIClient.shared.uploadVideo(data: videoData, mimeType: mimeType)
        } catch {
            // 403 falls through here. The video picker is hidden for free
            // users so a subscriber-only response shouldn't normally reach
            // this branch; no subscription copy surfaces either way per the
            // iOS-free-app direction.
            composeLog.error("uploadVideo failed: \(error)")
            errorMessage = "Failed to upload video: \(error.localizedDescription)"
            selectedVideo = nil
        }
    }

    private func postMessage() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        let text = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSubmit else { return }
        let tagList = tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let isoScheduled = scheduledDate.map {
            ISO8601DateFormatter().string(from: $0)
        }
        let uploadedImages = imageUploader.uploadedURLs
        let urls = uploadedImages.isEmpty ? nil : uploadedImages
        let videoUrls = uploadedVideoURL.map { [$0] }
        // Cross-post params only when the user is a subscriber and not replying.
        let crossPostEnabled = canUseSubscriberFeatures && !isReply
        let mastodonIds = crossPostEnabled && !selectedMastodonIds.isEmpty ? Array(selectedMastodonIds) : nil
        let linkedInOn = crossPostEnabled && crossPostLinkedIn && hasLinkedIn
        do {
            let result = try await APIClient.shared.postMessage(
                content: text,
                publiclyVisible: publiclyVisible,
                parentId: replyTo?.id,
                tags: tagList.isEmpty ? nil : tagList,
                scheduledAt: isoScheduled,
                imageUrls: urls,
                videoUrls: videoUrls,
                pushedMessageId: repostOf?.id,
                mastodonProviderIds: mastodonIds,
                crossPostToBluesky: crossPostEnabled && crossPostBluesky ? true : nil,
                crossPostToLinkedIn: linkedInOn ? true : nil,
                linkedInTargets: linkedInOn ? resolvedLinkedInTargets : nil,
                linkedInLinkAsFirstComment: linkedInOn && linkedInLinkAsFirstComment ? true : nil,
                crossPostToTwitter: crossPostEnabled && crossPostTwitter ? true : nil,
                organizationId: selectedOrgId
            )
            lastCrossPostResults = result.crossPostResults
            lastCrossPostUrls = result.message.crossPostUrls ?? []
            if !isReply && !isRepost {
                store.insertFeedMessage(result.message)
            }
            showSuccess = true
            if isReply || isRepost {
                dismiss()
            }
        } catch APIError.status(401) {
            authState.handleUnauthorized()
        } catch APIError.server(let message) {
            errorMessage = message
        } catch APIError.status(403) {
            errorMessage = "You may need to verify your email before posting."
        } catch {
            composeLog.error("postMessage failed: \(error)")
            errorMessage = "Connection failed. Please try again."
        }
    }
}
