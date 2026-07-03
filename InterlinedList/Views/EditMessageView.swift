//
//  EditMessageView.swift
//  InterlinedList
//

import SwiftUI

struct EditMessageView: View {
    let message: Message
    let onSave: (Message) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var content: String
    @State private var publiclyVisible: Bool
    @State private var scheduledDate: Date
    @State private var isLoading = false
    @State private var errorMessage: String?

    private let originalScheduledDate: Date?
    private var isScheduled: Bool { originalScheduledDate != nil }

    init(message: Message, onSave: @escaping (Message) -> Void) {
        self.message = message
        self.onSave = onSave
        _content = State(initialValue: message.content)
        _publiclyVisible = State(initialValue: message.publiclyVisible ?? true)
        let parsed = message.scheduledAt.flatMap { EditMessageView.parseISO($0) }
        self.originalScheduledDate = parsed
        _scheduledDate = State(initialValue: parsed ?? Date().addingTimeInterval(3600))
    }

    private static func parseISO(_ iso: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Content", text: $content, axis: .vertical)
                        .lineLimit(5...15)
                    Toggle("Public", isOn: $publiclyVisible)
                }

                if isScheduled {
                    Section("Scheduled for") {
                        DatePicker(
                            "Send at",
                            selection: $scheduledDate,
                            in: Date()...,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                    }
                }

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }

                Section {
                    Button {
                        Task { await save() }
                    } label: {
                        HStack {
                            if isLoading {
                                ProgressView()
                                    .frame(width: 20, height: 20)
                            }
                            Text("Save")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(isLoading || content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .navigationTitle("Edit Message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func save() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            // Reschedule first when the send time changed (scheduled, unpublished messages only).
            if isScheduled, let original = originalScheduledDate,
               abs(scheduledDate.timeIntervalSince(original)) > 1 {
                let iso = ISO8601DateFormatter().string(from: scheduledDate)
                _ = try await APIClient.shared.patchScheduledMessage(id: message.id, scheduledAt: iso, config: nil)
            }
            let contentChanged = trimmed != message.content || publiclyVisible != (message.publiclyVisible ?? true)
            if contentChanged {
                let updated = try await APIClient.shared.editMessage(id: message.id, content: trimmed, publiclyVisible: publiclyVisible)
                onSave(updated)
            }
            dismiss()
        } catch APIError.server(let msg) {
            errorMessage = msg
        } catch {
            errorMessage = "Failed to save changes."
        }
    }
}

#Preview {
    EditMessageView(
        message: Message(
            id: "1",
            content: "Sample message content",
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
            tags: nil,
            digCount: nil,
            dugByMe: nil,
            crossPostUrls: nil
        ),
        onSave: { _ in }
    )
}
