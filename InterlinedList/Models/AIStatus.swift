//
//  AIStatus.swift
//  InterlinedList
//

import Foundation

/// Daily AI budget. `/api/ai/status` reports `remaining`; the `suggest` and
/// `generate` responses omit it, so it falls back to the difference — both calls
/// decrement the same 50/day counter.
struct AIQuota: Codable, Equatable {
    let usedToday: Int
    let dailyLimit: Int
    private let reportedRemaining: Int?

    var remaining: Int { reportedRemaining ?? max(0, dailyLimit - usedToday) }
    var isExhausted: Bool { remaining <= 0 }

    enum CodingKeys: String, CodingKey {
        case usedToday
        case dailyLimit
        case reportedRemaining = "remaining"
    }

    init(usedToday: Int, dailyLimit: Int, remaining: Int? = nil) {
        self.usedToday = usedToday
        self.dailyLimit = dailyLimit
        self.reportedRemaining = remaining
    }
}

/// `GET /api/ai/status`. Free to call — it is how a client learns whether to
/// surface AI at all.
struct AIStatus: Codable, Equatable {
    /// The single gate for every AI affordance. AI is included with the
    /// subscription; there are no user-supplied provider keys, so nothing else
    /// on this payload may gate a control.
    let subscriber: Bool
    /// Display metadata only — never a precondition.
    let providers: [String]?
    /// Display metadata only — never a precondition.
    let defaultModels: [String: String]?
    let quota: AIQuota?

    /// Attribution line for a sheet footer, e.g. "Powered by Claude Sonnet 5".
    var attribution: String? {
        guard let provider = providers?.first,
              let model = defaultModels?[provider]
        else { return nil }
        let name = model
            .split(separator: "-")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
        return "Powered by \(name)"
    }
}

/// Token accounting returned alongside a suggestion. Informational.
struct AIUsage: Codable, Equatable {
    let inputTokens: Int
    let outputTokens: Int
    let model: String
}

/// Client-side mirror of the server's `lib/ai/limits.ts`. These gate the UI so a
/// request that the server would reject with `invalid_input` is never sent — and
/// never billed against the daily quota. The server remains authoritative.
enum AILimits {
    /// Minimum composer content before the two series generators activate.
    static let composerMinWords = 10

    static let messageSeriesRange = 3...12
    static let messageSeriesDefaultCount = 5
    static let articleSeriesRange = 2...6
    static let articleSeriesDefaultCount = 4

    /// Max words of free-text input per feature.
    static func maxInputWords(_ feature: AIFeature) -> Int {
        switch feature {
        case .writingAssist: return 1500
        case .poweredTemplate: return 300
        case .messageSeries: return 500
        case .poweredDocument: return 500
        case .articleSeries: return 500
        }
    }

    static func countWords(_ text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    /// Whether `text` is long enough for the composer's series generators.
    static func meetsSeriesMinimum(_ text: String) -> Bool {
        countWords(text) >= composerMinWords
    }
}
