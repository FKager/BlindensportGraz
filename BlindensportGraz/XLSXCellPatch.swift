import Foundation

/// Shared cell-rewriting helpers for patching blank cells inside a real
/// .xlsx template's sheet XML — the same technique `TeilnehmerlisteExporter`
/// pioneered for the Sport Austria "TeilnehmerInnenliste" template, factored
/// out here so `PraeExporter` (a second official-template-based export) can
/// reuse it instead of a second hand-rolled copy. `TeilnehmerlisteExporter`
/// itself is left untouched — not worth the regression risk of refactoring
/// an already-shipped, tested export path just to share four small functions.
enum XLSXCellPatch {
    /// Every target cell is a self-closing blank in a pristine template
    /// (`<c r="C3" s="65"/>`) — this rewrites it into a valued cell while
    /// preserving whatever style attributes (`s="N"`) it already carried.
    static func replaceCell(in xml: String, ref: String, build: (String) -> String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "<c r=\"\(ref)\"([^>]*)/>"),
              let match = regex.firstMatch(in: xml, range: NSRange(xml.startIndex..., in: xml)),
              let attrsRange = Range(match.range(at: 1), in: xml),
              let fullRange = Range(match.range, in: xml) else { return xml }
        let attrs = String(xml[attrsRange])
        return xml.replacingCharacters(in: fullRange, with: build(attrs))
    }

    static func setText(in xml: String, ref: String, value: String) -> String {
        replaceCell(in: xml, ref: ref) { attrs in
            "<c r=\"\(ref)\"\(attrs) t=\"inlineStr\"><is><t>\(xmlEscape(value))</t></is></c>"
        }
    }

    static func setNumber(in xml: String, ref: String, value: Double) -> String {
        replaceCell(in: xml, ref: ref) { attrs in
            "<c r=\"\(ref)\"\(attrs)><v>\(value)</v></c>"
        }
    }

    static func xmlEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    // MARK: - Overwriting an already-filled reference file
    //
    // The functions above only match a *blank* self-closing cell
    // (`<c r="C3" s="65"/>`), which is all a pristine, never-opened template
    // ever contains. `TrainingsfrequenzlisteExporter` instead patches a real,
    // already-filled-in club document (data/Trainingsfrequenzliste_Torball_2026.xlsx)
    // as its template, per explicit user request to use that exact file/layout
    // — so most target cells already carry a value, type, or (for the "ges. TL"
    // total row) a shared formula. `overwriteCell` matches either shape.

    /// Matches a cell whether it's a blank self-closing element or already
    /// carries content (`t="s"` shared-string ref, inline value, formula —
    /// anything up to the first `</c>`), and rebuilds it keeping only its
    /// style (`s="N"`), discarding any old type/value/formula.
    static func overwriteCell(in xml: String, ref: String, build: (String) -> String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "<c r=\"\(ref)\"([^>]*?)(?:/>|>.*?</c>)", options: [.dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: xml, range: NSRange(xml.startIndex..., in: xml)),
              let attrsRange = Range(match.range(at: 1), in: xml),
              let fullRange = Range(match.range, in: xml) else { return xml }
        let styleAttr = styleAttribute(in: String(xml[attrsRange]))
        return xml.replacingCharacters(in: fullRange, with: build(styleAttr))
    }

    private static func styleAttribute(in attrs: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "s=\"\\d+\""),
              let match = regex.firstMatch(in: attrs, range: NSRange(attrs.startIndex..., in: attrs)),
              let range = Range(match.range, in: attrs) else { return "" }
        return " \(attrs[range])"
    }

    /// Sets inline text, or — if `value` is empty — reverts the cell to a
    /// blank self-closing element (needed for e.g. unused date columns/person
    /// rows that the reference file's own template rows already had content
    /// or borders for).
    static func setInlineText(in xml: String, ref: String, value: String) -> String {
        overwriteCell(in: xml, ref: ref) { styleAttr in
            guard !value.isEmpty else { return "<c r=\"\(ref)\"\(styleAttr)/>" }
            return "<c r=\"\(ref)\"\(styleAttr) t=\"inlineStr\"><is><t>\(xmlEscape(value))</t></is></c>"
        }
    }

    static func setCellNumber(in xml: String, ref: String, value: Double) -> String {
        overwriteCell(in: xml, ref: ref) { styleAttr in
            "<c r=\"\(ref)\"\(styleAttr)><v>\(value)</v></c>"
        }
    }

    static func clearCell(in xml: String, ref: String) -> String {
        overwriteCell(in: xml, ref: ref) { styleAttr in "<c r=\"\(ref)\"\(styleAttr)/>" }
    }

    /// Updates only the cached `<v>` of a formula cell (e.g. the "ges. TL"
    /// row's `COUNTIF(D8:D31,"j")` shared formula), leaving the `<f>` intact
    /// — Excel/Numbers recalculate on open regardless, but a stale cached
    /// value would still show wrong in non-recalculating previewers (e.g.
    /// iOS QuickLook) until then.
    static func setFormulaCachedValue(in xml: String, ref: String, value: Double) -> String {
        guard let regex = try? NSRegularExpression(pattern: "<c r=\"\(ref)\"[^>]*>.*?<v>[^<]*</v>", options: [.dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: xml, range: NSRange(xml.startIndex..., in: xml)),
              let fullRange = Range(match.range, in: xml) else { return xml }
        let matched = String(xml[fullRange])
        guard let vRegex = try? NSRegularExpression(pattern: "<v>[^<]*</v>"),
              let vMatch = vRegex.firstMatch(in: matched, range: NSRange(matched.startIndex..., in: matched)),
              let vRange = Range(vMatch.range, in: matched) else { return xml }
        let replaced = matched.replacingCharacters(in: vRange, with: "<v>\(value)</v>")
        return xml.replacingCharacters(in: fullRange, with: replaced)
    }
}
