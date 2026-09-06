//
//  AISeriesLoading.swift
//  InterlinedList
//

import Foundation

/// Copy and step logic for the series-generation wait. The suggest call reports
/// no real progress and routinely runs tens of seconds, so a rotating caption is
/// what separates "working" from "hung". Pure, so the clamping is testable.
enum AISeriesLoading {
    static func captions(for feature: AIFeature) -> [String] {
        switch feature {
        case .messageSeries:
            return ["Reading your draft", "Planning the posts", "Writing each message", "Polishing the series"]
        case .articleSeries:
            return ["Reading your draft", "Outlining the articles", "Drafting each piece", "Polishing the series"]
        default:
            return ["Working"]
        }
    }

    static func title(for feature: AIFeature) -> String {
        switch feature {
        case .messageSeries: return "Generating your message series…"
        case .articleSeries: return "Generating your article series…"
        default: return "Generating…"
        }
    }

    /// Advance one caption every `step` seconds, clamped to the last one so the
    /// sequence settles instead of implying endless work.
    static func stepIndex(elapsed: TimeInterval, captionCount: Int, step: TimeInterval = 2.5) -> Int {
        guard captionCount > 0 else { return 0 }
        let raw = Int(max(0, elapsed) / step)
        return min(raw, captionCount - 1)
    }
}
