//
//  FollowRequestsView.swift
//  InterlinedList
//

import SwiftUI

struct FollowRequestsView: View {
    @EnvironmentObject var authState: AuthState
    @State private var requests: [FollowRequest] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading && requests.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage {
                ContentUnavailableView {
                    Label("Unable to load", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Retry") { Task { await load() } }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if requests.isEmpty {
                ContentUnavailableView {
                    Label("No Requests", systemImage: "person.crop.circle.badge.checkmark")
                } description: {
                    Text("No pending follow requests.")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(requests) { request in
                        FollowRequestListRow(request: request) { userId, approved in
                            Task { await handle(userId: userId, approved: approved) }
                        }
                    }
                }
                .refreshable { await load() }
            }
        }
        .navigationTitle("Follow Requests")
        .navigationBarTitleDisplayMode(.large)
        .task { await load() }
    }

    private func load() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            requests = try await APIClient.shared.followRequests()
        } catch APIError.status(401) {
            authState.handleUnauthorized()
        } catch {
            errorMessage = "Could not load follow requests."
        }
    }

    private func handle(userId: String, approved: Bool) async {
        do {
            if approved {
                try await APIClient.shared.approveFollowRequest(userId: userId)
            } else {
                try await APIClient.shared.rejectFollowRequest(userId: userId)
            }
            requests.removeAll { $0.user?.id == userId }
        } catch APIError.status(401) {
            authState.handleUnauthorized()
        } catch {}
    }
}

private struct FollowRequestListRow: View {
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
                if let createdAt = request.createdAt {
                    Text(formatDate(createdAt))
                        .font(.ilMono(10))
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
    NavigationStack {
        FollowRequestsView()
            .environmentObject(AuthState())
    }
}
