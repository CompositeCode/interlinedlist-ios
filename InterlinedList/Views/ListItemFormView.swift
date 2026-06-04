//
//  ListItemFormView.swift
//  InterlinedList
//

import SwiftUI

struct ListItemFormView: View {
    let schema: [ListPropertyDef]
    let existingItem: ListItem?
    let onSave: ([String: JSONValue]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var fieldValues: [String: String] = [:]
    @State private var boolValues: [String: Bool] = [:]
    @State private var dateValues: [String: Date] = [:]
    @State private var showValidationErrors = false

    private var isEditMode: Bool { existingItem != nil }

    private var visibleProps: [ListPropertyDef] {
        schema.filter { $0.isVisible }.sorted { $0.displayOrder < $1.displayOrder }
    }

    private var isValid: Bool {
        visibleProps.filter(\.isRequired).allSatisfy { prop in
            switch prop.propertyType {
            case "boolean":
                return true
            default:
                let val = fieldValues[prop.propertyKey] ?? ""
                return !val.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
        }
    }

    init(schema: [ListPropertyDef], existingItem: ListItem?, onSave: @escaping ([String: JSONValue]) -> Void) {
        self.schema = schema
        self.existingItem = existingItem
        self.onSave = onSave

        var fields: [String: String] = [:]
        var bools: [String: Bool] = [:]
        var dates: [String: Date] = [:]

        for prop in schema.filter(\.isVisible) {
            let raw = existingItem?.rowData[prop.propertyKey]
            switch prop.propertyType {
            case "boolean":
                bools[prop.propertyKey] = raw?.boolValue ?? (prop.defaultValue == "true")
            case "date":
                let str = raw?.displayString ?? prop.defaultValue ?? ""
                dates[prop.propertyKey] = Self.parseDate(str) ?? Date()
                fields[prop.propertyKey] = str
            case "number":
                fields[prop.propertyKey] = raw?.displayString ?? (prop.defaultValue ?? "")
            default:
                fields[prop.propertyKey] = raw?.displayString ?? (prop.defaultValue ?? "")
            }
        }

        _fieldValues = State(initialValue: fields)
        _boolValues = State(initialValue: bools)
        _dateValues = State(initialValue: dates)
    }

    var body: some View {
        NavigationStack {
            Form {
                ForEach(visibleProps) { prop in
                    Section {
                        fieldRow(for: prop)
                        if showValidationErrors && prop.isRequired && prop.propertyType != "boolean" {
                            let val = fieldValues[prop.propertyKey] ?? ""
                            if val.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text("\(prop.propertyName) is required")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }
                    } header: {
                        HStack {
                            Text(prop.propertyName)
                            if prop.isRequired { Text("*").foregroundStyle(.red) }
                        }
                    } footer: {
                        if let help = prop.helpText, !help.isEmpty {
                            Text(help)
                        }
                    }
                }
            }
            .navigationTitle(isEditMode ? "Edit Item" : "Add Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { attemptSave() }
                }
            }
        }
    }

    @ViewBuilder
    private func fieldRow(for prop: ListPropertyDef) -> some View {
        switch prop.propertyType {
        case "boolean":
            Toggle(prop.propertyName, isOn: Binding(
                get: { boolValues[prop.propertyKey] ?? false },
                set: { boolValues[prop.propertyKey] = $0 }
            ))

        case "textarea":
            TextEditor(text: Binding(
                get: { fieldValues[prop.propertyKey] ?? "" },
                set: { fieldValues[prop.propertyKey] = $0 }
            ))
            .frame(minHeight: 80)

        case "email":
            TextField(prop.placeholder ?? prop.propertyName, text: Binding(
                get: { fieldValues[prop.propertyKey] ?? "" },
                set: { fieldValues[prop.propertyKey] = $0 }
            ))
            .keyboardType(.emailAddress)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()

        case "url":
            TextField(prop.placeholder ?? prop.propertyName, text: Binding(
                get: { fieldValues[prop.propertyKey] ?? "" },
                set: { fieldValues[prop.propertyKey] = $0 }
            ))
            .keyboardType(.URL)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()

        case "number":
            TextField(prop.placeholder ?? prop.propertyName, text: Binding(
                get: { fieldValues[prop.propertyKey] ?? "" },
                set: { fieldValues[prop.propertyKey] = $0 }
            ))
            .keyboardType(.decimalPad)

        case "date":
            DatePicker(
                prop.propertyName,
                selection: Binding(
                    get: { dateValues[prop.propertyKey] ?? Date() },
                    set: { dateValues[prop.propertyKey] = $0 }
                ),
                displayedComponents: .date
            )
            .labelsHidden()

        default:
            TextField(prop.placeholder ?? prop.propertyName, text: Binding(
                get: { fieldValues[prop.propertyKey] ?? "" },
                set: { fieldValues[prop.propertyKey] = $0 }
            ))
        }
    }

    private func attemptSave() {
        guard isValid else {
            showValidationErrors = true
            return
        }
        var rowData: [String: JSONValue] = [:]
        for prop in visibleProps {
            switch prop.propertyType {
            case "boolean":
                rowData[prop.propertyKey] = .bool(boolValues[prop.propertyKey] ?? false)
            case "number":
                let str = fieldValues[prop.propertyKey] ?? ""
                if let d = Double(str) {
                    rowData[prop.propertyKey] = .number(d)
                } else if !str.isEmpty {
                    rowData[prop.propertyKey] = .string(str)
                }
            case "date":
                if let date = dateValues[prop.propertyKey] {
                    let iso = ISO8601DateFormatter()
                    iso.formatOptions = [.withInternetDateTime]
                    rowData[prop.propertyKey] = .string(iso.string(from: date))
                }
            default:
                let str = fieldValues[prop.propertyKey] ?? ""
                if !str.isEmpty {
                    rowData[prop.propertyKey] = .string(str)
                }
            }
        }
        onSave(rowData)
        dismiss()
    }

    private static func parseDate(_ str: String) -> Date? {
        guard !str.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: str) { return d }
        iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: str)
    }
}

#Preview("Add mode — multi-field schema") {
    let schema = [
        ListPropertyDef(id: "1", propertyKey: "title", propertyName: "Title", propertyType: "text", displayOrder: 0, isVisible: true, isRequired: true, defaultValue: nil, helpText: "The main name", placeholder: "e.g. Dune"),
        ListPropertyDef(id: "2", propertyKey: "read", propertyName: "Have Read", propertyType: "boolean", displayOrder: 1, isVisible: true, isRequired: false, defaultValue: nil, helpText: nil, placeholder: nil),
        ListPropertyDef(id: "3", propertyKey: "price", propertyName: "Price", propertyType: "number", displayOrder: 2, isVisible: true, isRequired: false, defaultValue: nil, helpText: nil, placeholder: "0.00"),
        ListPropertyDef(id: "4", propertyKey: "url", propertyName: "Link", propertyType: "url", displayOrder: 3, isVisible: true, isRequired: false, defaultValue: nil, helpText: nil, placeholder: "https://"),
    ]
    ListItemFormView(schema: schema, existingItem: nil) { _ in }
}

#Preview("Edit mode — pre-populated") {
    let schema = [
        ListPropertyDef(id: "1", propertyKey: "title", propertyName: "Title", propertyType: "text", displayOrder: 0, isVisible: true, isRequired: true, defaultValue: nil, helpText: nil, placeholder: nil),
        ListPropertyDef(id: "2", propertyKey: "read", propertyName: "Have Read", propertyType: "boolean", displayOrder: 1, isVisible: true, isRequired: false, defaultValue: nil, helpText: nil, placeholder: nil),
    ]
    let item = ListItem(id: "r1", rowData: ["title": .string("Dune"), "read": .bool(true)], rowNumber: 1, createdAt: nil)
    ListItemFormView(schema: schema, existingItem: item) { _ in }
}
