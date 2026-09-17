//
//  CrossPostLinksView.swift
//  InterlinedList
//

import SwiftUI

/// Renders the "Cross-posted to" destination chips for a message. Shared by the
/// thread view and the message detail view so both present cross-posts identically.
struct CrossPostLinksView: View {
    let urls: [CrossPostUrl]
    /// Cross-post reply counts, keyed by platform. Empty until the detail view has
    /// fetched them; entries that are `unsupported` or `error` are simply absent.
    var replyCounts: [String: Int] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Cross-posted to")
                .font(.ilMono(10))
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(urls) { crossPost in
                        chip(crossPost)
                    }
                }
            }
        }
        .padding(.top, 2)
    }

    @ViewBuilder
    private func chip(_ crossPost: CrossPostUrl) -> some View {
        let count = replyCounts[crossPost.platform.lowercased()]
        let label = HStack(spacing: 4) {
            Label(crossPost.destinationName, systemImage: icon(crossPost.platform))
            if let count {
                Text("\(count)")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("\(count) replies on \(crossPost.destinationName)")
            }
        }
        .font(.ilMono(11))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(ILColor.surface2)
        .clipShape(Capsule())
        if let urlString = crossPost.url, let url = URL(string: urlString) {
            Link(destination: url) { label }
                .accessibilityLabel("Open on \(crossPost.destinationName)")
        } else {
            label.foregroundStyle(.secondary)
        }
    }

    private func icon(_ platform: String) -> String {
        switch platform.lowercased() {
        case "bluesky": return "cloud"
        case "linkedin": return "briefcase"
        case "twitter": return "xmark"
        case "mastodon": return "number"
        default: return "link"
        }
    }
}

#Preview {
    CrossPostLinksView(urls: [
        CrossPostUrl(platform: "mastodon", url: "https://techhub.social/@x/1", instanceName: "techhub.social", instanceUrl: nil, statusId: "1", cid: nil, uri: nil),
        CrossPostUrl(platform: "bluesky", url: "https://bsky.app/x", instanceName: nil, instanceUrl: nil, statusId: nil, cid: "abc", uri: "at://x")
    ], replyCounts: ["mastodon": 4, "bluesky": 12])
    .padding()
}
