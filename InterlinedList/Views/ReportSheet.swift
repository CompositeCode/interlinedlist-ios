//
//  ReportSheet.swift
//  InterlinedList
//

import SwiftUI

enum ReportTarget: Identifiable {
    case message(id: String)
    case user(id: String, username: String)

    var id: String {
        switch self {
        case .message(let id): return "message:\(id)"
        case .user(let id, _): return "user:\(id)"
        }
    }

    var title: String {
        switch self {
        case .message: return "Report Post"
        case .user(_, let username): return "Report @\(username)"
        }
    }
}

struct ReportSheet: View {
    let target: ReportTarget
    let onDismiss: () -> Void

    @EnvironmentObject private var authState: AuthState
    @State private var selectedReason: ReportReason = .spam
    @State private var detail = ""
    @State private var isSubmitting = false
    @State private var submitted = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Reason") {
                    Picker("Reason", selection: $selectedReason) {
                        ForEach(ReportReason.allCases) { reason in
                            Text(reason.displayName).tag(reason)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section("Additional details (optional)") {
                    TextField("Describe the issue…", text: $detail, axis: .vertical)
                        .lineLimit(3...6)
                        .font(.ilBody())
                }

                if let error {
                    Section {
                        Text(error).foregroundStyle(.red).font(.ilMono())
                    }
                }

                if submitted {
                    Section {
                        Label("Report submitted. Thank you.", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
            }
            .navigationTitle(target.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onDismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSubmitting {
                        ProgressView()
                    } else if submitted {
                        Button("Done") { onDismiss() }
                    } else {
                        Button("Submit") {
                            Task { await submit() }
                        }
                        .accessibilityLabel("Submit report")
                    }
                }
            }
        }
    }

    private func submit() async {
        error = nil
        isSubmitting = true
        defer { isSubmitting = false }
        let detailText = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            switch target {
            case .message(let id):
                try await APIClient.shared.reportMessage(
                    id: id,
                    reason: selectedReason,
                    detail: detailText.isEmpty ? nil : detailText
                )
            case .user(let id, _):
                try await APIClient.shared.reportUser(
                    id: id,
                    reason: selectedReason,
                    detail: detailText.isEmpty ? nil : detailText
                )
            }
            submitted = true
        } catch APIError.status(401) {
            authState.handleUnauthorized()
        } catch {
            self.error = "Failed to submit report. Please try again."
        }
    }
}

#Preview {
    ReportSheet(target: .message(id: "abc"), onDismiss: {})
        .environmentObject(AuthState())
}
