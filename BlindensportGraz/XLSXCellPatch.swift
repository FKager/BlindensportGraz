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
}
