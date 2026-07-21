//
//  ListSchemaDraft.swift
//  InterlinedList
//

import Foundation

struct DraftProperty: Identifiable, Equatable {
    let id: String
    var propertyKey: String
    var propertyName: String
    var propertyType: String
    var isVisible: Bool
    var isRequired: Bool
    // Preserved through round-trips even though the v1 editor doesn't expose them.
    var defaultValue: String?
    var helpText: String?
    var placeholder: String?

    static let supportedTypes: [String] = ["text", "number", "boolean", "date", "url", "email"]

    /// New (unsaved) properties carry a synthetic id so the structured schema
    /// update knows to create rather than update them.
    var isNew: Bool { id.hasPrefix("new-") }

    init(from def: ListPropertyDef) {
        self.id = def.id
        self.propertyKey = def.propertyKey
        self.propertyName = def.propertyName
        self.propertyType = def.propertyType
        self.isVisible = def.isVisible
        self.isRequired = def.isRequired
        self.defaultValue = def.defaultValue
        self.helpText = def.helpText
        self.placeholder = def.placeholder
    }

    init(id: String, propertyKey: String, propertyName: String, propertyType: String,
         isVisible: Bool, isRequired: Bool,
         defaultValue: String? = nil, helpText: String? = nil, placeholder: String? = nil) {
        self.id = id
        self.propertyKey = propertyKey
        self.propertyName = propertyName
        self.propertyType = propertyType
        self.isVisible = isVisible
        self.isRequired = isRequired
        self.defaultValue = defaultValue
        self.helpText = helpText
        self.placeholder = placeholder
    }

    static func newBlank() -> DraftProperty {
        DraftProperty(
            id: "new-" + UUID().uuidString,
            propertyKey: "",
            propertyName: "",
            propertyType: "text",
            isVisible: true,
            isRequired: false
        )
    }
}

enum ListSchemaDraft {
    static let titleMaxLength = 120

    /// Columns a brand-new list starts with. The backend requires at least one
    /// column at creation, so seed a primary "Title" text column the user can
    /// rename or retype before creating.
    static func starterColumns() -> [DraftProperty] {
        var title = DraftProperty.newBlank()
        title.propertyName = "Title"
        return [title]
    }

    static func isTitleValid(_ title: String) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let count = trimmed.count
        return count >= 1 && count <= titleMaxLength
    }

    static func metadataChanged(
        originalTitle: String,
        originalDescription: String,
        originalIsPublic: Bool,
        title: String,
        description: String,
        isPublic: Bool
    ) -> Bool {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedTitle != originalTitle
            || trimmedDescription != originalDescription
            || isPublic != originalIsPublic
    }

    static func schemaChanged(original: [DraftProperty], current: [DraftProperty]) -> Bool {
        original != current
    }

    /// Serializes properties into the DSL string the backend's POST /api/lists example uses
    /// (e.g. "Title:text, Author:text"). Properties with an empty trimmed name are skipped.
    /// Note: this format loses `isVisible`, `isRequired`, and `displayOrder` — acceptable for v1.
    static func serializeSchemaDSL(_ properties: [DraftProperty]) -> String {
        properties
            .compactMap { prop -> String? in
                let trimmed = prop.propertyName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return nil }
                return "\(trimmed):\(prop.propertyType)"
            }
            .joined(separator: ", ")
    }

    /// Derive a snake_case property key from a display name (for new properties).
    /// "Have Read?" → "have_read". Falls back to "field" when nothing remains.
    static func slugifyKey(_ name: String) -> String {
        let lowered = name.lowercased()
        let mapped = lowered.map { ch -> Character in
            (ch.isLetter || ch.isNumber) ? ch : "_"
        }
        let collapsed = String(mapped)
            .split(separator: "_", omittingEmptySubsequences: true)
            .joined(separator: "_")
        return collapsed.isEmpty ? "field" : collapsed
    }

    /// Maps the draft list into the structured PUT /api/lists/[id]/schema body.
    /// Array order drives `displayOrder`. New properties (synthetic id) omit `id`
    /// and get a slugified key; existing properties keep their id and original key
    /// (the backend rejects propertyKey renames). Properties with an empty name are
    /// dropped, which the backend treats as a soft-delete.
    static func structuredProperties(_ properties: [DraftProperty]) -> [SchemaPropertyInput] {
        properties.enumerated().compactMap { index, prop in
            let name = prop.propertyName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            let key = prop.isNew
                ? (prop.propertyKey.isEmpty ? slugifyKey(name) : prop.propertyKey)
                : prop.propertyKey
            return SchemaPropertyInput(
                id: prop.isNew ? nil : prop.id,
                propertyKey: key,
                propertyName: name,
                propertyType: prop.propertyType,
                displayOrder: index,
                isVisible: prop.isVisible,
                isRequired: prop.isRequired,
                defaultValue: prop.defaultValue,
                helpText: prop.helpText,
                placeholder: prop.placeholder
            )
        }
    }

    static func isSchemaValid(_ properties: [DraftProperty]) -> Bool {
        for prop in properties {
            let trimmed = prop.propertyName.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return false }
            if !DraftProperty.supportedTypes.contains(prop.propertyType) { return false }
        }
        return true
    }

    /// Gate for the create-list form: the backend requires at least one column,
    /// and every column must be named with a supported type (no silently-dropped
    /// blank rows). Empty array is invalid.
    static func hasCreatableColumns(_ properties: [DraftProperty]) -> Bool {
        !properties.isEmpty && isSchemaValid(properties)
    }
}
