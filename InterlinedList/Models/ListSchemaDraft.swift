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

    static let supportedTypes: [String] = ["text", "number", "boolean", "date", "url", "email"]

    init(from def: ListPropertyDef) {
        self.id = def.id
        self.propertyKey = def.propertyKey
        self.propertyName = def.propertyName
        self.propertyType = def.propertyType
        self.isVisible = def.isVisible
        self.isRequired = def.isRequired
    }

    init(id: String, propertyKey: String, propertyName: String, propertyType: String, isVisible: Bool, isRequired: Bool) {
        self.id = id
        self.propertyKey = propertyKey
        self.propertyName = propertyName
        self.propertyType = propertyType
        self.isVisible = isVisible
        self.isRequired = isRequired
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

    static func isSchemaValid(_ properties: [DraftProperty]) -> Bool {
        for prop in properties {
            let trimmed = prop.propertyName.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return false }
            if !DraftProperty.supportedTypes.contains(prop.propertyType) { return false }
        }
        return true
    }
}
