//
//  ScheduledMessagesView.swift
//  InterlinedList
//

import SwiftUI

struct ScheduledMessagesView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var range = "week"
    @State private var messages: [Message] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var messageToEdit: Message?

    private let ranges = [
        ("today", "Today"),
        ("week", "This Week"),
        ("month", "This Month"),
    ]

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && messages.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = errorMessage, messages.isEmpty {
                    ContentUnavailableView {
                        Label("Unable to load", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Retry") { Task { await load() } }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if messages.isEmpty {
                    ContentUnavailableView {
                        Label("No Scheduled Posts", systemImage: "calendar")
                    } description: {
                        Text("No posts scheduled for this period.")
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(messages) { message in
                        Button {
                            messageToEdit = message
                        } label: {
                            ScheduledMessageRow(message: message)
                        }
                        .buttonStyle(.plain)
                    }
                    .refreshable { await load() }
                }
            }
            .navigationTitle("Scheduled")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .principal) {
                    Picker("Range", selection: $range) {
                        ForEach(ranges, id: \.0) { key, label in
                            Text(label).tag(key)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(minWidth: 220)
                }
            }
            .task { await load() }
            .onChange(of: range) { _, _ in Task { await load() } }
            .sheet(item: $messageToEdit, onDismiss: { Task { await load() } }) { message in
                EditMessageView(message: message) { _ in }
            }
        }
    }

    private func load() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            messages = try await APIClient.shared.scheduledMessages(range: range)
        } catch APIError.server(let msg) {
            errorMessage = msg
        } catch {
            // The calendar entry point in FeedView is hidden for free users,
            // so 403 from this subscriber-only endpoint shouldn't normally
            // reach the UI. Generic message preserves strict-silence on
            // subscription state.
            errorMessage = "Could not load scheduled posts."
        }
    }
}

private struct ScheduledMessageRow: View {
    let message: Message

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(message.content)
                .font(.body)
            HStack {
                if message.publiclyVisible == false {
                    Label("Private", systemImage: "lock.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let scheduledAt = message.scheduledAt {
                    Text(formatScheduledDate(scheduledAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if let tags = message.tags, !tags.isEmpty {
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
        .padding(.vertical, 4)
    }

    private func formatScheduledDate(_ iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) {
            return date.formatted(.dateTime.month().day().hour().minute())
        }
        return iso
    }
}

#Preview {
    ScheduledMessagesView()
}
