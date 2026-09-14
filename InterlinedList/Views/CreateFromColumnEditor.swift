//
//  CreateFromColumnEditor.swift
//  InterlinedList
//

import SwiftUI

/// One editable column in the "Create from…" sheet.
///
/// Carries its own stable `id` so renaming a column doesn't churn SwiftUI's list
/// identity — `MaterializeFieldConfig.propertyKey` is the wire identity and can
/// change as the user types a new column's name.
struct CreateFromColumn: Identifiable {
    let id = UUID()
    var name: String
    var type: String
    /// The source attribute this column reads from. `nil` = a user-added empty
    /// column, which the server fills with "".
    var sourceKey: String?
    var isRequired: Bool?
    var options: [String]?
    /// The key a source-mapped column arrived with; preserved so the mapping
    /// survives a rename.
    let originalKey: String?

    init(from config: MaterializeFieldConfig) {
        name = config.propertyName
        type = config.propertyType
        sourceKey = config.sourceKey
        isRequired = config.isRequired
        options = config.options
        originalKey = config.propertyKey
    }

    init(name: String = "", type: String = "text") {
        self.name = name
        self.type = type
        sourceKey = nil
        isRequired = nil
        options = nil
        originalKey = nil
    }

    /// Wire config. A source-mapped column keeps its original key; a user-added
    /// one derives a key from its name so the server's duplicate-key check and
    /// row projection both line up.
    func config(fallbackIndex: Int) -> MaterializeFieldConfig {
        let key = originalKey ?? Self.slug(name, fallback: "column_\(fallbackIndex + 1)")
        return MaterializeFieldConfig(
            propertyKey: key,
            propertyName: name.trimmingCharacters(in: .whitespacesAndNewlines),
            propertyType: type,
            isRequired: isRequired,
            options: options,
            sourceKey: sourceKey
        )
    }

    static func slug(_ value: String, fallback: String) -> String {
        let lowered = value.lowercased()
        var out = ""
        var lastWasSeparator = false
        for char in lowered {
            if char.isLetter || char.isNumber {
                out.append(char)
                lastWasSeparator = false
            } else if !out.isEmpty && !lastWasSeparator {
                out.append("_")
                lastWasSeparator = true
            }
        }
        while out.hasSuffix("_") { out.removeLast() }
        return out.isEmpty ? fallback : out
    }
}

/// The rename / retype / remove row for one column.
struct CreateFromColumnRow: View {
    @Binding var column: CreateFromColumn

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Column name", text: $column.name)
                .font(.ilBody())
                .accessibilityLabel("Column name")
            HStack {
                Picker("Type", selection: $column.type) {
                    ForEach(MaterializeFieldConfig.supportedTypes, id: \.self) { type in
                        Text(Self.typeLabel(type)).tag(type)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityLabel("Column type for \(column.name.isEmpty ? "new column" : column.name)")
                Spacer()
                if column.sourceKey == nil {
                    Text("empty")
                        .font(.ilMono(11))
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Empty column, not filled from the source")
                }
            }
        }
        .padding(.vertical, 2)
    }

    static func typeLabel(_ type: String) -> String {
        switch type {
        case "textarea": return "Long text"
        case "boolean": return "Yes / No"
        case "url": return "Link"
        default: return type.capitalized
        }
    }
}

#Preview("Source-mapped column") {
    @Previewable @State var column = CreateFromColumn(
        from: MaterializeFieldConfig(propertyKey: "content", propertyName: "Content", propertyType: "textarea", sourceKey: "content")
    )
    Form { CreateFromColumnRow(column: $column) }
}

#Preview("User-added empty column") {
    @Previewable @State var column = CreateFromColumn(name: "Notes")
    Form { CreateFromColumnRow(column: $column) }
}
