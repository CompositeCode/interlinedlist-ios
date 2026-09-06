//
//  MultiSelectField.swift
//  InterlinedList
//

import SwiftUI

/// A menu-backed multi-select for a `multiselect` list column whose options are
/// known at runtime — today that's a GitHub-backed list's labels and assignees,
/// fetched per repo.
///
/// The bound value stays a **comma-separated string** because that is what the
/// backend's `rowDataToIssuePayload` reads back (`labels.split(",")`), and what
/// it writes when it maps an issue to a row (`labels.map(name).join(",")`).
/// Values already on the row that aren't in `options` are kept and shown, so
/// editing a row never silently drops a label the picker doesn't know about.
struct MultiSelectField: View {
    let label: String
    let options: [String]
    @Binding var value: String

    private var selected: [String] {
        value
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Options plus anything already selected that the repo no longer offers.
    private var allChoices: [String] {
        options + selected.filter { !options.contains($0) }
    }

    private var summary: String {
        selected.isEmpty ? "None" : selected.joined(separator: ", ")
    }

    var body: some View {
        Menu {
            ForEach(allChoices, id: \.self) { option in
                Button {
                    toggle(option)
                } label: {
                    if selected.contains(option) {
                        Label(option, systemImage: "checkmark")
                    } else {
                        Text(option)
                    }
                }
            }
            if !selected.isEmpty {
                Divider()
                Button(role: .destructive) {
                    value = ""
                } label: {
                    Label("Clear all", systemImage: "xmark.circle")
                }
            }
        } label: {
            HStack {
                Text(summary)
                    .font(.ilBody())
                    .foregroundStyle(selected.isEmpty ? Color.secondary : Color.primary)
                    .lineLimit(1)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.ilMono(11))
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .accessibilityLabel("\(label): \(summary)")
    }

    private func toggle(_ option: String) {
        var current = selected
        if let index = current.firstIndex(of: option) {
            current.remove(at: index)
        } else {
            current.append(option)
        }
        // Join without spaces to match how the backend writes labels back.
        value = current.joined(separator: ",")
    }
}

#Preview("Some selected") {
    @Previewable @State var value = "bug,docs"
    Form {
        MultiSelectField(label: "Labels", options: ["bug", "docs", "enhancement", "good first issue"], value: $value)
    }
}

#Preview("None selected") {
    @Previewable @State var value = ""
    Form {
        MultiSelectField(label: "Assignees", options: ["adron", "octocat"], value: $value)
    }
}
