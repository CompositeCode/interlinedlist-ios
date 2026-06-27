//
//  SettingsView.swift
//  InterlinedList
//

import SwiftUI
import SafariServices

/// App settings: appearance, posting defaults, connected accounts, notification
/// preferences, informational links, and sign-out. Consolidates account-level
/// controls that previously lived only on the profile / edit-profile screens.
struct SettingsView: View {
    @EnvironmentObject private var authState: AuthState
    @Environment(\.dismiss) private var dismiss

    @State private var theme: String = "system"
    @State private var defaultPublic: Bool = true
    @State private var showAdvanced: Bool = false
    @State private var settingsError: String?
    @State private var safariLink: SafariLink?

    private let aboutLinks: [(title: String, path: String)] = [
        ("Blog", "/blog"),
        ("Pricing", "/pricing"),
        ("Terms of Service", "/terms"),
        ("Privacy Policy", "/privacy"),
        ("Branding", "/help/branding"),
    ]

    var body: some View {
        NavigationStack {
            Form {
                appearanceSection
                postingSection
                accountsSection
                notificationsSection
                aboutSection
                if let settingsError {
                    Section { Text(settingsError).font(.caption).foregroundStyle(.red) }
                }
                Section {
                    Button(role: .destructive) {
                        authState.logout()
                    } label: {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear(perform: syncFromUser)
            .sheet(item: $safariLink) { link in
                SafariView(url: link.url).ignoresSafeArea()
            }
        }
    }

    private func syncFromUser() {
        guard let user = authState.user else { return }
        theme = user.theme ?? "system"
        defaultPublic = user.defaultPubliclyVisible ?? true
        showAdvanced = user.showAdvancedPostSettings ?? false
    }

    // MARK: - Sections

    private var appearanceSection: some View {
        Section("Appearance") {
            Picker("Theme", selection: $theme) {
                Text("System").tag("system")
                Text("Light").tag("light")
                Text("Dark").tag("dark")
            }
            .onChange(of: theme) { _, newValue in
                Task { await save(theme: newValue) }
            }
        }
    }

    private var postingSection: some View {
        Section("Posting") {
            Toggle("Default to public", isOn: $defaultPublic)
                .onChange(of: defaultPublic) { _, newValue in
                    Task { await save(defaultVisibility: newValue) }
                }
            Toggle("Show advanced post settings", isOn: $showAdvanced)
                .onChange(of: showAdvanced) { _, newValue in
                    Task { await save(showAdvancedPostSettings: newValue) }
                }
            if let maxLen = authState.user?.maxMessageLength {
                LabeledContent("Max message length", value: maxLen, format: .number)
            }
        }
    }

    @ViewBuilder
    private var accountsSection: some View {
        if authState.user?.isSubscriber == true {
            Section("Accounts") {
                NavigationLink {
                    LinkedIdentitiesView().environmentObject(authState)
                } label: {
                    Label("Connected accounts", systemImage: "link")
                }
            }
        }
    }

    private var notificationsSection: some View {
        Section("Notifications") {
            NavigationLink {
                NotificationPreferencesView().environmentObject(authState)
            } label: {
                Label("Notification preferences", systemImage: "bell.badge")
            }
        }
    }

    private var aboutSection: some View {
        Section("About") {
            ForEach(aboutLinks, id: \.path) { link in
                Button {
                    if let url = URL(string: "https://interlinedlist.com" + link.path) {
                        safariLink = SafariLink(url: url)
                    }
                } label: {
                    HStack {
                        Text(link.title).foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "arrow.up.right.square").foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Persistence

    private func save(theme: String? = nil, defaultVisibility: Bool? = nil, showAdvancedPostSettings: Bool? = nil) async {
        settingsError = nil
        do {
            let updated = try await APIClient.shared.updateUserSettings(
                theme: theme,
                defaultVisibility: defaultVisibility,
                showAdvancedPostSettings: showAdvancedPostSettings
            )
            authState.updateUser(updated)
        } catch APIError.status(401) {
            authState.handleUnauthorized()
        } catch {
            settingsError = "Could not save settings."
        }
    }
}

/// Identifiable wrapper so a URL can drive a Safari sheet via `.sheet(item:)`.
struct SafariLink: Identifiable {
    let id = UUID()
    let url: URL
}

/// Thin wrapper around SFSafariViewController for in-app web content.
struct SafariView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }
    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

// MARK: - Notification preferences

/// Settings → Notifications. Renders one row per supported channel for each
/// event the server actually emits (GAP §B3: real catalog only — dig/push/follow,
/// channels limited to push/inApp, no email). Toggles persist immediately.
struct NotificationPreferencesView: View {
    @EnvironmentObject private var authState: AuthState
    @State private var events: [NotificationPreference] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var actionError: String?

    var body: some View {
        Group {
            if isLoading && events.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error, events.isEmpty {
                ContentUnavailableView {
                    Label("Unable to load", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Retry") { Task { await load() } }
                }
            } else {
                List {
                    if let actionError {
                        Section { Text(actionError).font(.caption).foregroundStyle(.red) }
                    }
                    ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                        Section {
                            if event.supportsPush {
                                channelToggle(index: index, label: "Push", keyPath: \.push)
                            }
                            if event.supportsInApp {
                                channelToggle(index: index, label: "In-app", keyPath: \.inApp)
                            }
                        } header: {
                            Text(event.label)
                        } footer: {
                            if let desc = event.description, !desc.isEmpty {
                                Text(desc)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func channelToggle(index: Int, label: String, keyPath: WritableKeyPath<NotificationChannels, Bool?>) -> some View {
        Toggle(label, isOn: Binding(
            get: { events[index].channels[keyPath: keyPath] ?? false },
            set: { newValue in
                events[index].channels[keyPath: keyPath] = newValue
                Task { await save(events[index]) }
            }
        ))
    }

    private func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            events = try await APIClient.shared.notificationPreferences()
        } catch APIError.status(401) {
            authState.handleUnauthorized()
        } catch {
            self.error = "Could not load notification settings."
        }
    }

    private func save(_ event: NotificationPreference) async {
        actionError = nil
        do {
            let updated = try await APIClient.shared.updateNotificationPreference(key: event.key, channels: event.channels)
            if let idx = events.firstIndex(where: { $0.key == updated.key }) {
                events[idx] = updated
            }
        } catch {
            actionError = "Could not update “\(event.label).”"
            await load()
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AuthState())
}
