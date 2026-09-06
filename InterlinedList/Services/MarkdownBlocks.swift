//
//  MarkdownBlocks.swift
//  InterlinedList
//

import Foundation

/// A lightweight markdown block splitter, ported from the backend's
/// `lib/materialize/markdown-blocks.ts` so the "Create from a document" preview
/// shows the same rows the server will build.
///
/// Deliberately not a full CommonMark parser — it handles only the constructs
/// that matter for row extraction: ATX headings, unordered/ordered list items,
/// blockquotes, fenced code, and paragraphs. Keep in sync with the backend if
/// that splitter changes.
enum MarkdownBlocks {

    /// Nested so it doesn't collide with `MarkdownView`'s own rendering-side
    /// `MarkdownBlock`, which is a different concern (display, not extraction).
    enum BlockType: String, Equatable {
        case heading
        case listItem = "list-item"
        case paragraph
        case code
        case quote
    }

    struct Block: Equatable {
        let type: BlockType
        /// Heading level (1–6) or list nesting depth (1-based); 0 when not applicable.
        let level: Int
        /// Block text with the leading marker (`#`, `-`, `>`) stripped.
        let text: String
        /// Nearest preceding heading text; empty before the first heading.
        let section: String
    }

    static func split(_ markdown: String) -> [Block] {
        var blocks: [Block] = []
        let lines = markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")

        var section = ""
        var paragraph: [String] = []

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            let text = paragraph.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                blocks.append(Block(type: .paragraph, level: 0, text: text, section: section))
            }
            paragraph = []
        }

        var i = 0
        while i < lines.count {
            let line = lines[i]

            if let fence = fenceMarker(line) {
                flushParagraph()
                var code: [String] = []
                i += 1
                while i < lines.count, !isClosingFence(lines[i], marker: fence) {
                    code.append(lines[i])
                    i += 1
                }
                i += 1 // skip the closing fence (or run off the end)
                blocks.append(Block(type: .code, level: 0, text: code.joined(separator: "\n"), section: section))
                continue
            }

            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                flushParagraph()
                i += 1
                continue
            }

            if let heading = parseHeading(line) {
                flushParagraph()
                section = heading.text
                blocks.append(Block(type: .heading, level: heading.level, text: heading.text, section: heading.text))
                i += 1
                continue
            }

            if let item = parseListItem(line) {
                flushParagraph()
                blocks.append(Block(type: .listItem, level: item.level, text: item.text, section: section))
                i += 1
                continue
            }

            if let quote = parseQuote(line) {
                flushParagraph()
                blocks.append(Block(type: .quote, level: 0, text: quote, section: section))
                i += 1
                continue
            }

            paragraph.append(line.trimmingCharacters(in: .whitespaces))
            i += 1
        }

        flushParagraph()
        return blocks
    }

    /// Blocks worth turning into rows: headings + list items, else every block.
    static func rowBlocks(_ markdown: String) -> [Block] {
        let all = split(markdown)
        let primary = all.filter { $0.type == .heading || $0.type == .listItem }
        return primary.isEmpty ? all : primary
    }

    // MARK: - Line parsing

    /// `` ``` `` or `~~~` (3+), optionally indented. Returns the fence character.
    private static func fenceMarker(_ line: String) -> Character? {
        let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })
        guard let first = trimmed.first, first == "`" || first == "~" else { return nil }
        let run = trimmed.prefix(while: { $0 == first }).count
        return run >= 3 ? first : nil
    }

    private static func isClosingFence(_ line: String, marker: Character) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.allSatisfy({ $0 == marker }) else { return false }
        return trimmed.count >= 3
    }

    private static func parseHeading(_ line: String) -> (level: Int, text: String)? {
        guard line.first == "#" else { return nil }
        let hashes = line.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(hashes) else { return nil }
        let rest = line.dropFirst(hashes)
        // The backend regex requires at least one space after the hashes.
        guard let separator = rest.first, separator == " " || separator == "\t" else { return nil }
        return (hashes, rest.trimmingCharacters(in: .whitespaces))
    }

    private static func parseListItem(_ line: String) -> (level: Int, text: String)? {
        let indentChars = line.prefix(while: { $0 == " " || $0 == "\t" })
        // Tabs count as two spaces, matching the backend's `replace(/\t/g, "  ")`.
        let indent = indentChars.reduce(0) { $0 + ($1 == "\t" ? 2 : 1) }
        var rest = Substring(line.dropFirst(indentChars.count))
        guard let marker = rest.first else { return nil }

        if marker == "-" || marker == "*" || marker == "+" {
            rest = rest.dropFirst()
        } else if marker.isNumber {
            let digits = rest.prefix(while: { $0.isNumber })
            let afterDigits = rest.dropFirst(digits.count)
            guard let delimiter = afterDigits.first, delimiter == "." || delimiter == ")" else { return nil }
            rest = afterDigits.dropFirst()
        } else {
            return nil
        }

        guard let separator = rest.first, separator == " " || separator == "\t" else { return nil }
        return (indent / 2 + 1, rest.trimmingCharacters(in: .whitespaces))
    }

    private static func parseQuote(_ line: String) -> String? {
        var rest = Substring(line.drop(while: { $0 == " " || $0 == "\t" }))
        guard rest.first == ">" else { return nil }
        rest = rest.dropFirst()
        // The backend's `>\s?` consumes at most one space after the marker; the
        // captured text is then trimmed, so a plain trim matches.
        return rest.trimmingCharacters(in: .whitespaces)
    }
}
