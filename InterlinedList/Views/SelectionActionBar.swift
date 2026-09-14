//
//  SelectionActionBar.swift
//  InterlinedList
//

import SwiftUI

/// One row in a multi-select picking mode: a checkmark, a headline, and an
/// optional caption above it.
///
/// Selection modes swap this in for the screen's normal row. The real rows carry
/// their own controls (dig, reply, inline field editing) which would swallow the
/// selection tap, so picking uses a plain summary rather than overlaying a
/// checkbox on an interactive row.
struct SelectableSummaryRow: View {
    let title: String
    var caption: String?
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? ILColor.primary : Color.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    if let caption {
                        Text(caption)
                            .font(.ilMono(11))
                            .foregroundStyle(.secondary)
                    }
                    Text(title)
                        .font(.ilBody(15))
                        .lineLimit(3)
                        .foregroundStyle(.primary)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(caption.map { "\($0): \(title)" } ?? title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// The bottom bar of a multi-select picking mode: cancel, a live count, and the
/// action the selection feeds.
struct SelectionActionBar: View {
    let countLabel: String
    let actionTitle: String
    let isActionEnabled: Bool
    let onCancel: () -> Void
    let onAction: () -> Void

    var body: some View {
        HStack {
            Button("Cancel", action: onCancel)
            Spacer()
            Text(countLabel)
                .font(.ilMono(12))
                .foregroundStyle(.secondary)
                .accessibilityLabel("\(countLabel) selected")
            Spacer()
            Button(actionTitle, action: onAction)
                .disabled(!isActionEnabled)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.regularMaterial)
    }
}

#Preview("Rows and bar") {
    VStack(spacing: 0) {
        List {
            SelectableSummaryRow(title: "Dune", caption: nil, isSelected: true) {}
            SelectableSummaryRow(title: "Tacos in Seattle — where?", caption: "Adron", isSelected: false) {}
        }
        SelectionActionBar(countLabel: "1 row", actionTitle: "Create from…",
                           isActionEnabled: true, onCancel: {}, onAction: {})
    }
}
