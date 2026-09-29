import SwiftUI
import SwiftData

/// Minimal line-based Markdown renderer for the welcome screen's content —
/// headers, bullet/numbered lists and inline emphasis/links (via
/// `AttributedString(markdown:)`) per line. Deliberately not a full
/// CommonMark implementation (nested lists, tables, code blocks) — this only
/// needs to render a short welcome note.
struct MarkdownContentView: View {
    let markdown: String

    private var lines: [String] {
        markdown.components(separatedBy: .newlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                blockView(for: line)
            }
        }
    }

    @ViewBuilder
    private func blockView(for rawLine: String) -> some View {
        let line = rawLine.trimmingCharacters(in: .whitespaces)
        if line.isEmpty {
            Spacer().frame(height: 4)
        } else if line.hasPrefix("### ") {
            inlineText(String(line.dropFirst(4))).font(.title3.bold())
        } else if line.hasPrefix("## ") {
            inlineText(String(line.dropFirst(3))).font(.title2.bold())
        } else if line.hasPrefix("# ") {
            inlineText(String(line.dropFirst(2))).font(.largeTitle.bold())
        } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
            HStack(alignment: .top, spacing: Theme.Spacing.s) {
                Text("•")
                inlineText(String(line.dropFirst(2)))
            }
        } else if let dotRange = line.range(of: ". "),
                  !line[..<dotRange.lowerBound].isEmpty,
                  line[..<dotRange.lowerBound].allSatisfy(\.isNumber) {
            HStack(alignment: .top, spacing: Theme.Spacing.s) {
                Text(String(line[..<dotRange.upperBound]))
                inlineText(String(line[dotRange.upperBound...]))
            }
        } else {
            inlineText(line).font(.body)
        }
    }

    private func inlineText(_ text: String) -> Text {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        if let attributed = try? AttributedString(markdown: text, options: options) {
            return Text(attributed)
        }
        return Text(text)
    }
}
