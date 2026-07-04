//
//  NotificationsView.swift
//  InterlinedList
//

import SwiftUI

struct NotificationsView: View {
    @EnvironmentObject var authState: AuthState
    @Environment(\.dismiss) private var dismiss

    @State private var notifications: [AppNotification] = []
    @State private var followRequests: [FollowRequest] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedNotification: AppNotification?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && notifications.isEmpty && followRequests.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = errorMessage, notifications.isEmpty, followRequests.isEmpty {
                    ContentUnavailableView {
                        Label("Unable to load", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Retry") { Task { await load() } }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if notifications.isEmpty && followRequests.isEmpty {
                    ContentUnavailableView {
                        Label("No Notifications", systemImage: "bell")
                    } description: {
                        Text("You're all caught up.")
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        if !followRequests.isEmpty {
                            Section("Follow Requests") {
                                ForEach(followRequests) { request in
                                    FollowRequestRow(request: request) { userId, approved in
                                        Task { await handleFollowRequest(userId: userId, approved: approved) }
                                    }
                                }
                            }
                        }
                        if !notifications.isEmpty {
                            Section("Notifications") {
                                ForEach(notifications) { notification in
                                    NotificationRow(notification: notification) {
                                        selectedNotification = notification
                                        Task { await markRead(notification) }
                                    }
                                }
                            }
                        }
                    }
                    .refreshable { await load() }
                }
            }
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                if !notifications.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Mark all read") {
                            Task { await markAllRead() }
                        }
                        .font(.ilMono())
                    }
                }
            }
            .task { await load() }
            .sheet(item: $selectedNotification) { notification in
                NotificationDetailView(notification: notification)
            }
        }
    }

    private func load() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadNotifications() }
            group.addTask { await self.loadFollowRequests() }
        }
    }

    private func loadNotifications() async {
        do {
            let response = try await APIClient.shared.notifications()
            notifications = response.items
        } catch APIError.status(401) {
            authState.handleUnauthorized()
        } catch APIError.status(403) {
            // Not a subscriber or endpoint not available — silently show empty
        } catch {
            if followRequests.isEmpty {
                errorMessage = "Could not load notifications."
            }
        }
    }

    private func loadFollowRequests() async {
        do {
            followRequests = try await APIClient.shared.followRequests()
        } catch APIError.status(401) {
            authState.handleUnauthorized()
        } catch {
            // Silently ignore — shown alongside notifications
        }
    }

    private func markRead(_ notification: AppNotification) async {
        do {
            try await APIClient.shared.markNotificationRead(id: notification.id)
            notifications = notifications.map {
                $0.id == notification.id
                    ? AppNotification(id: $0.id, message: $0.message, type: $0.type, read: true, createdAt: $0.createdAt, actorUsername: $0.actorUsername)
                    : $0
            }
        } catch {}
    }

    private func markAllRead() async {
        do {
            try await APIClient.shared.markAllNotificationsRead()
            notifications = notifications.map {
                AppNotification(id: $0.id, message: $0.message, type: $0.type, read: true, createdAt: $0.createdAt, actorUsername: $0.actorUsername)
            }
        } catch {}
    }

    private func handleFollowRequest(userId: String, approved: Bool) async {
        do {
            if approved {
                try await APIClient.shared.approveFollowRequest(userId: userId)
            } else {
                try await APIClient.shared.rejectFollowRequest(userId: userId)
            }
            followRequests.removeAll { $0.user?.id == userId }
        } catch APIError.status(401) {
            authState.handleUnauthorized()
        } catch {}
    }
}

private struct NotificationRow: View {
    let notification: AppNotification
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 10) {
                Circle()
                    .fill(notification.read == true ? Color.clear : ILColor.primary)
                    .frame(width: 8, height: 8)
                    .padding(.top, 5)
                VStack(alignment: .leading, spacing: 4) {
                    if let actor = notification.actorUsername {
                        Text("@\(actor)")
                            .font(.ilMono())
                            .foregroundStyle(.secondary)
                    }
                    Text(notification.message ?? "New notification")
                        .font(.ilBody(15))
                        .foregroundStyle(notification.read == true ? .secondary : .primary)
                    if let createdAt = notification.createdAt {
                        Text(formatDate(createdAt))
                            .font(.ilMono(10))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .buttonStyle(.plain)
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

private struct FollowRequestRow: View {
    let request: FollowRequest
    let onAction: (String, Bool) -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(request.user?.displayName ?? request.user?.username ?? "Someone")
                    .font(.ilBody(15))
                    .fontWeight(.medium)
                if let username = request.user?.username {
                    Text("@\(username)")
                        .font(.ilMono())
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let userId = request.user?.id {
                Button("Confirm") { onAction(userId, true) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                Button("Decline") { onAction(userId, false) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct NotificationDetailView: View {
    let notification: AppNotification
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let type = notification.type {
                        Text(typeLabel(type))
                            .font(.ilMono())
                            .fontWeight(.medium)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(ILColor.surface2)
                            .clipShape(Capsule())
                    }
                    if let actor = notification.actorUsername {
                        Label("@\(actor)", systemImage: "person")
                            .font(.ilBody(15))
                            .foregroundStyle(.secondary)
                    }
                    Text(notification.message ?? "No message")
                        .font(.ilBody())
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let createdAt = notification.createdAt {
                        Text(formatFullDate(createdAt))
                            .font(.ilMono())
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
            .navigationTitle("Notification")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func typeLabel(_ type: String) -> String {
        switch type {
        case "follow":  return "New Follower"
        case "mention": return "Mention"
        case "dig":     return "Dig"
        case "reply":   return "Reply"
        case "comment": return "Comment"
        default:        return type.capitalized
        }
    }

    private func formatFullDate(_ iso: String) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) {
            return DateFormatter.localizedString(from: date, dateStyle: .long, timeStyle: .short)
        }
        return iso
    }
}

#Preview {
    NotificationsView()
        .environmentObject(AuthState())
}
