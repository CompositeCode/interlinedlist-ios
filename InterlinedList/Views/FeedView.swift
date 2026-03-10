//
//  FeedView.swift
//  InterlinedList
//

import SwiftUI

struct FeedView: View {
    @EnvironmentObject var authState: AuthState
    @State private var messages: [Message] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var pagination: Pagination?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && messages.isEmpty {
                    ProgressView("Loading messages…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .frame(minWidth: 44, minHeight: 44)
                } else if let error = errorMessage, messages.isEmpty {
                    ContentUnavailableView {
                        Label("Unable to load", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Retry") {
                            Task { await loadMessages() }
                        }
                    }
                } else {
                    List {
                        ForEach(messages) { message in
                            MessageRow(message: message)
                        }
                        if let pagination = pagination, pagination.hasMore, !isLoading {
                            HStack {
                                Spacer()
                                ProgressView()
                                    .frame(width: 24, height: 24)
                                Spacer()
                            }
                            .onAppear {
                                Task { await loadMore() }
                            }
                        }
                    }
                    .refreshable {
                        await loadMessages()
                    }
                }
            }
            .navigationTitle("InterlinedList")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        Image("Logo")
                            .resizable()
                            .frame(width: 28, height: 28)
                            .clipped()
                        Text("InterlinedList")
                            .font(.headline)
                    }
                }
            }
            .task {
                await loadMessages()
            }
            .onChange(of: authState.user?.id) { _, _ in
                if authState.isLoggedIn {
                    Task { await loadMessages() }
                }
            }
        }
    }

    private func loadMessages() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            let (list, pag) = try await APIClient.shared.messages(limit: 50, offset: 0)
            messages = list
            pagination = pag
        } catch APIError.status(401) {
            authState.handleUnauthorized()
        } catch APIError.server(let message) {
            errorMessage = message
        } catch {
            errorMessage = "Connection failed. Please try again."
        }
    }

    private func loadMore() async {
        guard let pag = pagination, pag.hasMore else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let (list, pag) = try await APIClient.shared.messages(limit: 50, offset: messages.count)
            messages.append(contentsOf: list)
            pagination = pag
        } catch {
            errorMessage = "Failed to load more."
        }
    }
}

struct MessageRow: View {
    let message: Message

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(message.authorDisplay)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Text(formatDate(message.createdAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(message.content)
                .font(.body)
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
