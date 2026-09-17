//
//  ListRowComposeText.swift
//  InterlinedList
//

import Foundation

/// Builds the composer body for "Schedule a post from this row".
///
/// Plain text, not markdown — a message is not markdown on the wire, matching the
/// web's `lib/materialize/build-message.ts`. The row's headline comes from
/// `ListPropertyDef.primaryDisplayField(from:)` (never `schema.first`, which is
/// usually an id or a timestamp); the remaining visible fields follow as labelled
/// lines so the user can trim what they don't want before posting.
enum ListRowComposeText {

    static func body(listTitle: String, schema: [ListPropertyDef], row: [String: JSONValue]) -> String {
        let visible = schema
            .filter { $0.isVisible }
            .sorted { $0.displayOrder < $1.displayOrder }
        let headlineField = ListPropertyDef.primaryDisplayField(from: schema)

        var parts: [String] = []

        let trimmedTitle = listTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTitle.isEmpty { parts.append(trimmedTitle) }

        if let headlineField, let headline = value(for: headlineField, in: row) {
            parts.append(headline)
        }

        let details = visible
            .filter { $0.id != headlineField?.id }
            .compactMap { field -> String? in
                guard let value = value(for: field, in: row) else { return nil }
                let label = field.propertyName.trimmingCharacters(in: .whitespacesAndNewlines)
                return label.isEmpty ? value : "\(label): \(value)"
            }
        if !details.isEmpty { parts.append(details.joined(separator: "\n")) }

        return parts.joined(separator: "\n\n")
    }

    /// Nil for anything with no text to show, so empty cells don't become
    /// "Label: " noise the user has to delete.
    private static func value(for field: ListPropertyDef, in row: [String: JSONValue]) -> String? {
        guard let raw = row[field.propertyKey] else { return nil }
        let text = raw.displayString.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}
