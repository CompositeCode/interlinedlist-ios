//
//  MarkdownView.swift
//  InterlinedList
//

import SwiftUI

/// Native block-based Markdown renderer.
///
/// `Text(AttributedString(markdown:))` only renders inline styling — it silently
/// drops `![alt](url)` images and collapses block structure (headings, lists,
/// code, line breaks). This splits content into blocks and renders each natively,
/// including images via `AsyncImage`, so images inserted into a document actually
/// appear. Shared by the document reader, the public reader, and the editor preview.
struct MarkdownView: View {
    let content: String

    var body: some View {
        let blocks = MarkdownBlock.parse(content)
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            MarkdownBlock.inline(text)
                .font(headingFont(level))
                .foregroundStyle(ILColor.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, level <= 2 ? 4 : 0)
        case .paragraph(let text):
            MarkdownBlock.inline(text)
                .font(.ilBody(15))
                .foregroundStyle(ILColor.textBody)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .bulletList(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    listRow(marker: "•", text: item)
                }
            }
        case .orderedList(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    listRow(marker: "\(item.marker).", text: item.text)
                }
            }
        case .quote(let text):
            HStack(spacing: 8) {
                Rectangle()
                    .fill(ILColor.primary)
                    .frame(width: 3)
                MarkdownBlock.inline(text)
                    .font(.ilBody(15))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .fixedSize(horizontal: false, vertical: true)
        case .codeBlock(let code):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.ilMono(12))
                    .foregroundStyle(ILColor.textBody)
                    .padding(10)
            }
            .background(ILColor.surface2)
            .clipShape(RoundedRectangle(cornerRadius: ILMetric.radiusMd))
        case .image(let alt, let url):
            MarkdownImageView(alt: alt, urlString: url)
        case .rule:
            Divider()
        }
    }

    private func listRow(marker: String, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(marker)
                .font(.ilBody(15))
                .foregroundStyle(.secondary)
            MarkdownBlock.inline(text)
                .font(.ilBody(15))
                .foregroundStyle(ILColor.textBody)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return .ilDisplay(22)
        case 2: return .ilTitle(18)
        case 3: return .ilTitle(15)
        default: return .ilBody(14).weight(.bold)
        }
    }
}

/// Renders a remote Markdown image, mirroring the `AsyncImage` phase handling used
/// elsewhere (e.g. `FeedView`) but sized full-width for document reading.
private struct MarkdownImageView: View {
    let alt: String
    let urlString: String

    var body: some View {
        Group {
            if let url = URL(string: urlString), !urlString.isEmpty {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: ILMetric.radiusLg))
                    case .failure:
                        placeholder
                    case .empty:
                        ZStack {
                            ILColor.surface2
                            ProgressView()
                        }
                        .frame(height: 160)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: ILMetric.radiusLg))
                    @unknown default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .accessibilityLabel(alt.isEmpty ? "Image" : alt)
    }

    private var placeholder: some View {
        HStack(spacing: 6) {
            Image(systemName: "photo")
            Text(alt.isEmpty ? "Image unavailable" : alt)
                .font(.ilMono())
                .lineLimit(1)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, minHeight: 80)
        .background(ILColor.surface2)
        .clipShape(RoundedRectangle(cornerRadius: ILMetric.radiusLg))
    }
}

/// A parsed Markdown block. The parser is intentionally small: it recognizes the
/// block constructs the app produces (headings, lists, quotes, fenced code,
/// standalone images, rules) and treats everything else as an inline paragraph.
enum MarkdownBlock {
    case heading(level: Int, text: String)
    case paragraph(String)
    case bulletList([String])
    case orderedList([(marker: String, text: String)])
    case quote(String)
    case codeBlock(String)
    case image(alt: String, url: String)
    case rule

    /// Inline styling (bold/italic/links/code) without block collapsing. Block
    /// markers are stripped by the parser before the text reaches here.
    static func inline(_ string: String) -> Text {
        if let attributed = try? AttributedString(
            markdown: string,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return Text(attributed)
        }
        return Text(string)
    }

    static func parse(_ content: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        let lines = content.components(separatedBy: "\n")
        var paragraph: [String] = []
        var i = 0

        func flushParagraph() {
            let text = paragraph.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { blocks.append(.paragraph(text)) }
            paragraph.removeAll()
        }

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                flushParagraph()
                i += 1
                continue
            }

            if trimmed.hasPrefix("```") {
                flushParagraph()
                var code: [String] = []
                i += 1
                while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    code.append(lines[i])
                    i += 1
                }
                if i < lines.count { i += 1 }
                blocks.append(.codeBlock(code.joined(separator: "\n")))
                continue
            }

            if let image = parseImage(trimmed) {
                flushParagraph()
                blocks.append(.image(alt: image.alt, url: image.url))
                i += 1
                continue
            }

            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                flushParagraph()
                blocks.append(.rule)
                i += 1
                continue
            }

            if let heading = parseHeading(trimmed) {
                flushParagraph()
                blocks.append(.heading(level: heading.level, text: heading.text))
                i += 1
                continue
            }

            if trimmed.hasPrefix(">") {
                flushParagraph()
                var quoteLines: [String] = []
                while i < lines.count {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    guard t.hasPrefix(">") else { break }
                    quoteLines.append(String(t.dropFirst()).trimmingCharacters(in: .whitespaces))
                    i += 1
                }
                blocks.append(.quote(quoteLines.joined(separator: "\n")))
                continue
            }

            if isBullet(trimmed) {
                flushParagraph()
                var items: [String] = []
                while i < lines.count {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    guard isBullet(t) else { break }
                    items.append(String(t.dropFirst(2)).trimmingCharacters(in: .whitespaces))
                    i += 1
                }
                blocks.append(.bulletList(items))
                continue
            }

            if orderedMarker(trimmed) != nil {
                flushParagraph()
                var items: [(marker: String, text: String)] = []
                while i < lines.count {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    guard let marker = orderedMarker(t) else { break }
                    items.append(marker)
                    i += 1
                }
                blocks.append(.orderedList(items))
                continue
            }

            paragraph.append(line)
            i += 1
        }
        flushParagraph()
        return blocks
    }

    // MARK: - Line classifiers

    private static func parseImage(_ line: String) -> (alt: String, url: String)? {
        guard line.hasPrefix("!["), line.hasSuffix(")"),
              let separator = line.range(of: "](") else { return nil }
        let altStart = line.index(line.startIndex, offsetBy: 2)
        let alt = String(line[altStart..<separator.lowerBound])
        let url = String(line[separator.upperBound..<line.index(before: line.endIndex)])
            .trimmingCharacters(in: .whitespaces)
        guard !url.isEmpty else { return nil }
        return (alt, url)
    }

    private static func parseHeading(_ line: String) -> (level: Int, text: String)? {
        var level = 0
        var index = line.startIndex
        while index < line.endIndex, line[index] == "#", level < 6 {
            level += 1
            index = line.index(after: index)
        }
        guard level > 0, index < line.endIndex, line[index] == " " else { return nil }
        let text = String(line[line.index(after: index)...]).trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        return (level, text)
    }

    private static func isBullet(_ line: String) -> Bool {
        line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ")
    }

    private static func orderedMarker(_ line: String) -> (marker: String, text: String)? {
        let chars = Array(line)
        var i = 0
        while i < chars.count, chars[i].isNumber { i += 1 }
        guard i > 0, i + 1 < chars.count,
              chars[i] == "." || chars[i] == ")",
              chars[i + 1] == " " else { return nil }
        let marker = String(chars[0..<i])
        let text = String(chars[(i + 2)...]).trimmingCharacters(in: .whitespaces)
        return (marker, text)
    }
}

#Preview {
    ScrollView {
        MarkdownView(content: """
        # Heading One
        A paragraph with **bold**, *italic*, and a [link](https://example.com).

        ## Heading Two
        - First bullet
        - Second bullet

        1. Step one
        2. Step two

        > A quoted line.

        ![sample](https://example.com/image.jpg)

        ```
        let code = "block"
        ```
        """)
        .padding()
    }
}
