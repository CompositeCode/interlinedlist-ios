//
//  FindPeopleView.swift
//  InterlinedList
//

import SwiftUI

/// Prefix search over people (G6). Debounced `.searchable` list; tapping a row
/// opens that user's profile. An empty/blank query shows a neutral prompt rather
/// than firing a request (the backend rejects a blank `q` with 400).
struct FindPeopleView: View {
    @EnvironmentObject private var authState: AuthState
    @State private var query = ""
    @State private var results: [FollowUser] = []
    @State private var isSearching = false
    @State private var error: String?
    @State private var profileTarget: ProfileTarget?

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        Group {
            if trimmedQuery.isEmpty {
                ContentUnavailableView {
                    Label("Find people", systemImage: "magnifyingglass")
                } description: {
                    Text("Search by name or @username to find people to follow.")
                }
            } else if let error, results.isEmpty {
                ContentUnavailableView {
                    Label("Search failed", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Retry") { Task { await runSearch() } }
                }
            } else if isSearching && results.isEmpty {
                ProgressView("Searching…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if results.isEmpty {
                ContentUnavailableView.search(text: trimmedQuery)
            } else {
                List(results) { user in
                    Button {
                        profileTarget = ProfileTarget(username: user.username)
                    } label: {
                        PersonSearchRow(user: user)
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Find People")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Name or @username")
        .onChange(of: query) { _, newValue in
            if newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                results = []
                error = nil
            }
        }
        .task(id: query) {
            guard !trimmedQuery.isEmpty else { return }
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await runSearch()
        }
        .sheet(item: $profileTarget) { target in
            UserProfileView(username: target.username)
                .environmentObject(authState)
        }
    }

    private func runSearch() async {
        let q = trimmedQuery
        guard !q.isEmpty else { return }
        isSearching = true
        defer { isSearching = false }
        do {
            let users = try await APIClient.shared.searchUsers(query: q)
            guard !Task.isCancelled else { return }
            results = users
            error = nil
        } catch APIError.status(401) {
            authState.handleUnauthorized()
        } catch APIError.server(let msg) {
            error = msg
        } catch {
            self.error = "Search failed. Please try again."
        }
    }
}

private struct PersonSearchRow: View {
    let user: FollowUser

    var body: some View {
        HStack(spacing: 12) {
            avatar
            VStack(alignment: .leading, spacing: 2) {
                Text(user.displayNameOrUsername)
                    .font(.ilBody())
                    .foregroundStyle(.primary)
                Text("@\(user.username)")
                    .font(.ilMono())
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(user.displayNameOrUsername), @\(user.username)")
    }

    @ViewBuilder
    private var avatar: some View {
        if let avatarURL = user.avatar.flatMap({ URL(string: $0) }) {
            AsyncImage(url: avatarURL) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    Image(systemName: "person.circle.fill").resizable().scaledToFit()
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 40, height: 40)
            .clipShape(Circle())
        } else {
            Image(systemName: "person.circle.fill")
                .resizable().scaledToFit()
                .frame(width: 40, height: 40)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    NavigationStack {
        FindPeopleView()
            .environmentObject(AuthState())
    }
}
