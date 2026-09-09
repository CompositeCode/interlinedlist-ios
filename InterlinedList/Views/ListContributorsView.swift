//
//  ListContributorsView.swift
//  InterlinedList
//

import SwiftUI

/// Cascading avatars for the top contributors to a list, sized to sit inline in
/// the list detail header. Overflow beyond `maxAvatars` collapses into a "+N"
/// bubble, mirroring the web's `ContributorAvatarStack`.
struct ContributorAvatarStack: View {
    let contributors: [ListContributor]
    let total: Int
    var size: CGFloat = 28
    var maxAvatars: Int = 3

    private var shown: [ListContributor] { Array(contributors.prefix(maxAvatars)) }
    private var overflow: Int { max(0, total - shown.count) }
    private var overlap: CGFloat { size * 0.35 }

    var body: some View {
        HStack(spacing: -overlap) {
            ForEach(shown) { contributor in
                ContributorAvatar(avatar: contributor.avatar, size: size)
                    .overlay(Circle().stroke(ILColor.surface, lineWidth: 2))
            }
            if overflow > 0 {
                Text("+\(overflow)")
                    .font(.ilMono(size * 0.4))
                    .foregroundStyle(.white)
                    .frame(width: size, height: size)
                    .background(Color.secondary, in: Circle())
                    .overlay(Circle().stroke(ILColor.surface, lineWidth: 2))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.label(for: total))
    }

    static func label(for total: Int) -> String {
        total == 1 ? "1 contributor" : "\(total) contributors"
    }
}

/// The full ranked contributor set. The route returns everything at once, so
/// this scrolls rather than paging (the web's 6-per-page modal is a desktop
/// affordance). Row style mirrors `WatchersListView`.
struct ListContributorsSheet: View {
    let contributors: [ListContributor]
    let total: Int

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if contributors.isEmpty {
                    ContentUnavailableView {
                        Label("No contributors yet", systemImage: "person.2")
                    } description: {
                        Text("Nobody has added or edited rows on this list.")
                    }
                } else {
                    ForEach(contributors) { contributor in
                        ContributorRow(contributor: contributor)
                    }
                }
            }
            .navigationTitle("Contributors (\(total))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct ContributorRow: View {
    let contributor: ListContributor

    var body: some View {
        HStack(spacing: 12) {
            ContributorAvatar(avatar: contributor.avatar, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(contributor.displayNameOrUsername)
                    .font(.ilBody())
                Text("@\(contributor.username) · \(contributor.contributionSummary)")
                    .font(.ilMono())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(contributor.score)")
                .font(.ilMono())
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(ILColor.surface2)
                .clipShape(Capsule())
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(contributor.displayNameOrUsername), added \(contributor.addedCount), edited \(contributor.editedCount)"
        )
    }
}

/// Circular remote avatar with a person-glyph fallback, matching the watcher row.
private struct ContributorAvatar: View {
    let avatar: String?
    let size: CGFloat

    var body: some View {
        if let url = avatar.flatMap({ URL(string: $0) }) {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    placeholder
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
        } else {
            placeholder
                .frame(width: size, height: size)
                .clipShape(Circle())
        }
    }

    private var placeholder: some View {
        Image(systemName: "person.circle.fill")
            .resizable()
            .scaledToFit()
            .foregroundStyle(.secondary)
    }
}

#Preview("Stack") {
    ContributorAvatarStack(contributors: ListContributor.previewSet, total: 5)
        .padding()
}

#Preview("Sheet") {
    ListContributorsSheet(contributors: ListContributor.previewSet, total: 3)
}

private extension ListContributor {
    static let previewSet: [ListContributor] = [
        ListContributor(id: "u1", username: "adron", displayName: "Adron Hall",
                        avatar: nil, addedCount: 12, editedCount: 4, score: 16),
        ListContributor(id: "u2", username: "rhea", displayName: "Rhea Kim",
                        avatar: nil, addedCount: 7, editedCount: 1, score: 8),
        ListContributor(id: "u3", username: "sam", displayName: nil,
                        avatar: nil, addedCount: 2, editedCount: 3, score: 5)
    ]
}
