//
//  ListRowSorting.swift
//  InterlinedList
//

import Foundation

/// Sort direction for an in-list sort.
enum ListSortDirection: String, CaseIterable, Identifiable {
    case ascending, descending
    var id: String { rawValue }
    var label: String { self == .ascending ? "Ascending" : "Descending" }
    var symbol: String { self == .ascending ? "arrow.up" : "arrow.down" }
}

/// What the user picked in the sort menu. `nil` property means server order.
struct ListSortOrder: Equatable {
    var propertyKey: String
    var direction: ListSortDirection = .ascending
}

/// A value filter on one property. Composes with — never replaces — the GitHub
/// open/closed filter, which is applied separately by the view.
struct ListValueFilter: Equatable {
    var propertyKey: String
    var value: String
}

/// Sorting, filtering and searching rows of a list, kept out of the view so the
/// comparators are unit-testable without SwiftUI.
///
/// All of it is client-side over already-loaded rows: nothing here is sent to the
/// server, and no row-write behaviour is affected.
enum ListRowSorting {

    // MARK: - Search

    /// Case- and diacritic-insensitive substring match across the *visible* values
    /// of a row. Hidden columns are excluded so a search cannot match something the
    /// user cannot see.
    static func search(_ items: [ListItem], query: String, schema: [ListPropertyDef]) -> [ListItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return items }
        let visibleKeys = schema.filter(\.isVisible).map(\.propertyKey)
        return items.filter { item in
            visibleKeys.contains { key in
                guard let value = item.rowData[key]?.displayString, !value.isEmpty else { return false }
                return value.range(of: trimmed, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            }
        }
    }

    // MARK: - Filter

    static func filter(_ items: [ListItem], by filter: ListValueFilter?) -> [ListItem] {
        guard let filter else { return items }
        return items.filter { item in
            (item.rowData[filter.propertyKey]?.displayString ?? "") == filter.value
        }
    }

    /// The distinct values present for a property, for building the filter menu.
    /// Drawn from the rows rather than only `selectOptions`, because GitHub-backed
    /// lists send `[]` for their synthetic select options.
    static func distinctValues(of propertyKey: String, in items: [ListItem]) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for item in items {
            guard let value = item.rowData[propertyKey]?.displayString, !value.isEmpty else { continue }
            if seen.insert(value).inserted { ordered.append(value) }
        }
        return ordered.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// Properties worth offering a value filter on — enumerated or boolean types,
    /// where a finite value set makes a picker meaningful.
    static func filterableProperties(in schema: [ListPropertyDef]) -> [ListPropertyDef] {
        schema
            .filter(\.isVisible)
            .filter { ["select", "multiselect", "boolean", "checkbox"].contains($0.propertyType.lowercased()) }
            .sorted { $0.displayOrder < $1.displayOrder }
    }

    static func sortableProperties(in schema: [ListPropertyDef]) -> [ListPropertyDef] {
        schema.filter(\.isVisible).sorted { $0.displayOrder < $1.displayOrder }
    }

    // MARK: - Sort

    /// Type-aware, stable sort. Rows with no value for the sort column always sink
    /// to the bottom regardless of direction — an empty cell is "unknown", not
    /// "smallest", and flipping direction should not float blanks to the top.
    static func sort(_ items: [ListItem], by order: ListSortOrder?, schema: [ListPropertyDef]) -> [ListItem] {
        guard let order,
              let property = schema.first(where: { $0.propertyKey == order.propertyKey })
        else { return items }

        let indexed = items.enumerated().map { ($0.offset, $0.element) }
        let sorted = indexed.sorted { lhs, rhs in
            let l = value(lhs.1, order.propertyKey)
            let r = value(rhs.1, order.propertyKey)

            switch (l.isEmpty, r.isEmpty) {
            case (true, true): return lhs.0 < rhs.0
            case (true, false): return false
            case (false, true): return true
            case (false, false): break
            }

            if let result = compare(l, r, type: property.propertyType) {
                return order.direction == .ascending ? result : !result
            }
            return lhs.0 < rhs.0   // equal — keep the original order, so the sort is stable
        }
        return sorted.map(\.1)
    }

    private static func value(_ item: ListItem, _ key: String) -> String {
        (item.rowData[key]?.displayString ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Returns nil when the two values are equal, so the caller can fall back to the
    /// original index and keep the sort stable.
    private static func compare(_ l: String, _ r: String, type: String) -> Bool? {
        switch type.lowercased() {
        case "number", "currency", "percent":
            if let ln = Double(l), let rn = Double(r) {
                return ln == rn ? nil : ln < rn
            }
        case "boolean", "checkbox":
            let lb = boolValue(l), rb = boolValue(r)
            return lb == rb ? nil : (!lb && rb)
        case "date", "datetime":
            if let ld = date(from: l), let rd = date(from: r) {
                return ld == rd ? nil : ld < rd
            }
        default:
            break
        }
        // Text and anything that failed to parse as its declared type: a
        // localized, numeric-aware comparison so "Item 10" sorts after "Item 9".
        let result = l.localizedStandardCompare(r)
        return result == .orderedSame ? nil : result == .orderedAscending
    }

    private static func boolValue(_ raw: String) -> Bool {
        ["yes", "true", "1"].contains(raw.lowercased())
    }

    private static let isoWithFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let iso: ISO8601DateFormatter = ISO8601DateFormatter()

    private static func date(from raw: String) -> Date? {
        isoWithFraction.date(from: raw) ?? iso.date(from: raw)
    }
}
