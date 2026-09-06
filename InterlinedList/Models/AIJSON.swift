//
//  AIJSON.swift
//  InterlinedList
//

import Foundation

/// A lossless JSON value.
///
/// The AI artifact envelope carries model-authored sub-objects — a Powered
/// Template's DSL schema and its starter rows — that must survive the round trip
/// from `POST /api/ai/suggest` back into `POST /api/ai/generate` unchanged: the
/// server re-validates the confirmed artifact, and a renamed field key
/// (`scheduled_at` → `scheduledAt`) fails that check. `JSONValue` in `List.swift`
/// is scalar-only and can't carry them, and the shared `APIClient` decoder's
/// `convertFromSnakeCase` is exactly the mangling to avoid — the AI endpoints get
/// their own verbatim coders.
enum AIJSON: Codable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([AIJSON])
    case object([String: AIJSON])
    case null

    var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    var objectValue: [String: AIJSON]? {
        if case .object(let o) = self { return o }
        return nil
    }

    var arrayValue: [AIJSON]? {
        if case .array(let a) = self { return a }
        return nil
    }

    /// Flat rendering for a preview row. Arrays join with commas; objects and
    /// null render empty, since neither belongs in a single-line cell.
    var displayString: String {
        switch self {
        case .string(let s): return s
        case .int(let i): return String(i)
        case .double(let d): return d.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(d)) : String(d)
        case .bool(let b): return b ? "Yes" : "No"
        case .array(let a): return a.map { $0.displayString }.joined(separator: ", ")
        case .object, .null: return ""
        }
    }

    private struct DynamicKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    init(from decoder: Decoder) throws {
        if let container = try? decoder.container(keyedBy: DynamicKey.self) {
            var object: [String: AIJSON] = [:]
            for key in container.allKeys {
                object[key.stringValue] = try container.decode(AIJSON.self, forKey: key)
            }
            self = .object(object)
            return
        }
        if var container = try? decoder.unkeyedContainer() {
            var items: [AIJSON] = []
            while !container.isAtEnd {
                items.append(try container.decode(AIJSON.self))
            }
            self = .array(items)
            return
        }
        let single = try decoder.singleValueContainer()
        if single.decodeNil() { self = .null; return }
        if let b = try? single.decode(Bool.self) { self = .bool(b); return }
        // Int before Double so whole numbers re-encode as `1`, not `1.0`.
        if let i = try? single.decode(Int.self) { self = .int(i); return }
        if let d = try? single.decode(Double.self) { self = .double(d); return }
        if let s = try? single.decode(String.self) { self = .string(s); return }
        throw DecodingError.dataCorruptedError(
            in: single,
            debugDescription: "Unsupported JSON value"
        )
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .object(let object):
            var container = encoder.container(keyedBy: DynamicKey.self)
            for (key, value) in object {
                guard let codingKey = DynamicKey(stringValue: key) else { continue }
                try container.encode(value, forKey: codingKey)
            }
        case .array(let items):
            var container = encoder.unkeyedContainer()
            for item in items { try container.encode(item) }
        case .string(let s):
            var c = encoder.singleValueContainer()
            try c.encode(s)
        case .int(let i):
            var c = encoder.singleValueContainer()
            try c.encode(i)
        case .double(let d):
            var c = encoder.singleValueContainer()
            try c.encode(d)
        case .bool(let b):
            var c = encoder.singleValueContainer()
            try c.encode(b)
        case .null:
            var c = encoder.singleValueContainer()
            try c.encodeNil()
        }
    }
}
