//
//  AIPoweredTemplate.swift
//  InterlinedList
//

import Foundation

/// A Powered Template the AI personalizes into a list schema.
///
/// `templateKey` is a prompt hint the server folds into the instruction — it is
/// optional and unvalidated, so this client-side gallery mirrors the server's
/// `POWERED_TEMPLATES` for presentation only. Picking none is valid: the model
/// then works from the description alone.
struct AIPoweredTemplate: Identifiable, Equatable {
    let id: String
    let name: String
    let summary: String
    let icon: String
    let previewChips: [String]

    var promptPlaceholder: String {
        "e.g. \(examplePrompt)"
    }

    private var examplePrompt: String {
        switch id {
        case "messages_campaign": return "Launch week posts for the new release, across Bluesky and LinkedIn"
        case "article_series": return "A four-part series on migrating a Rails app to Postgres 17"
        case "software_workload": return "Backlog for the payments rewrite, with estimates and blockers"
        default: return "Track conference talks: event, date, status, slides URL"
        }
    }

    static let gallery: [AIPoweredTemplate] = [
        AIPoweredTemplate(
            id: "messages_campaign",
            name: "Messages Campaign",
            summary: "Plan and schedule a set of cross-posted messages around a single campaign.",
            icon: "📣",
            previewChips: ["Message", "Channels", "Status", "Scheduled At"]
        ),
        AIPoweredTemplate(
            id: "article_series",
            name: "Article Series",
            summary: "Outline a multi-part article or blog series from idea through publication.",
            icon: "📰",
            previewChips: ["Title", "Part", "Status", "Angle"]
        ),
        AIPoweredTemplate(
            id: "software_workload",
            name: "Software Workload",
            summary: "Track software work items across a backlog with type, status, and estimates.",
            icon: "⚙️",
            previewChips: ["Item", "Type", "Status", "Estimate"]
        ),
    ]
}
