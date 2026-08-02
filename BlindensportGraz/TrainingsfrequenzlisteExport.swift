import Foundation
import ZIPFoundation

/// Exports the Sport-Austria-federation-style "Trainingsfrequenzliste"
/// (training attendance register) — one row per team member, one column per
/// training date, "j"/"n" attendance per cell, plus a per-date total row.
///
/// The only real-world copy of this form found (ÖBSV/OÖBSV's
/// `Trainingsfrequenzliste.xls`, downloaded and reverse-engineered via
/// `xlrd` for this feature) is a legacy binary .xls (OLE2), NOT a zip-based
/// .xlsx — so unlike TeilnehmerlisteExporter/PraeExporter.exportMainForm
/// (which patch a real .xlsx template's XML in place), this can't be
/// patched the same way. Follows PraeExporter.exportDarstellung's precedent
/// instead: build a fresh, minimal-but-valid .xlsx from scratch that
/// reproduces the original's exact layout (title, "Verein/LV:"/"Sportart:"
/// header, "Trainingstage (Datum):" label, Nr./Vorname/Nachname/Verein
/// columns, one date column per training day, "ges. TL" total row, and the
/// original's own legend footnote text verbatim) but with real per-member
/// attendance filled in — deliberately reproducing the original's field set
/// as-is with no added columns (e.g. no per-member total column, which the
/// original doesn't have either).
enum TrainingsfrequenzlisteExporter {
    static func export(summary: TrainingsfrequenzlisteSummary, vereinName: String = "Grazer VSC") throws -> URL {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "de_AT")
        dateFormatter.dateFormat = "dd.MM."

        let periodLabel = "\(summary.halfYear.label) \(summary.year)"

        var rows: [[XLSXGridCell]] = []
        rows.append([.text("T R A I N I N G S F R E Q U E N Z L I S T E", bold: true)])
        rows.append([])
        rows.append([.text("Verein/LV:", bold: true), .text(vereinName), .text(""), .text("Sportart:", bold: true), .text(summary.team.sport)])
        rows.append([.text("Zeitraum:", bold: true), .text(periodLabel)])
        rows.append([])
        rows.append([.text("Trainingstage (Datum):", bold: true)])

        var headerRow: [XLSXGridCell] = [.text("Nr.", bold: true), .text("Vorname", bold: true),
                                          .text("Nachname", bold: true), .text("Verein", bold: true)]
        headerRow.append(contentsOf: summary.trainingDates.map { .text(dateFormatter.string(from: $0), bold: true) })
        rows.append(headerRow)

        for (index, person) in summary.people.enumerated() {
            var row: [XLSXGridCell] = [.text("\(index + 1)."), .text(person.firstName), .text(person.lastName), .text(vereinName)]
            row.append(contentsOf: summary.trainingDates.map { .text(person.attended(on: $0) ? "j" : "n") })
            rows.append(row)
        }

        var totalRow: [XLSXGridCell] = [.text(""), .text(""), .text("ges. TL", bold: true), .text("")]
        totalRow.append(contentsOf: summary.trainingDates.map { .number(Double(summary.totalPresent(on: $0))) })
        rows.append(totalRow)

        rows.append([])
        rows.append([.text("Trainingstage (Datum) bei anwesenden SportlerInnen \"j\" sonst \"n\" eintragen")])

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Trainingsfrequenzliste-\(UUID().uuidString).xlsx")
        try writeMinimalXLSX(rows: rows, sheetName: "Trainingsteiln", to: outputURL)
        return outputURL
    }
}

// MARK: - Minimal from-scratch .xlsx writer
//
// Deliberately self-contained rather than reusing PraeExport.swift's private
// writeMinimalXLSX — that one is `private` to its own file, and duplicating
// this small, stable writer avoids touching an already-shipped export path
// for a refactor (same reasoning XLSXCellPatch.swift's doc comment gives for
// leaving TeilnehmerlisteExporter unrefactored).

private enum XLSXGridCell {
    case text(String, bold: Bool = false)
    case number(Double, bold: Bool = false)
}

private func writeMinimalXLSX(rows: [[XLSXGridCell]], sheetName: String, to url: URL) throws {
    let contentTypes = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
    <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
    <Default Extension="xml" ContentType="application/xml"/>
    <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
    <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
    <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
    </Types>
    """

    let rootRels = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
    <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
    </Relationships>
    """

    let workbookRels = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
    <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
    <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
    </Relationships>
    """

    let workbook = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
    <sheets><sheet name="\(XLSXCellPatch.xmlEscape(sheetName))" sheetId="1" r:id="rId1"/></sheets>
    </workbook>
    """

    // cellXfs index 0 = default, 1 = bold (fontId 1) — the only two styles this export needs.
    let styles = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
    <fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><name val="Calibri"/></font></fonts>
    <fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills>
    <borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>
    <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
    <cellXfs count="2">
    <xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
    <xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/>
    </cellXfs>
    </styleSheet>
    """

    var sheetXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
    <sheetData>
    """
    for (rowIndex, row) in rows.enumerated() {
        let rowNumber = rowIndex + 1
        sheetXML += "<row r=\"\(rowNumber)\">"
        for (colIndex, cell) in row.enumerated() {
            let ref = "\(columnLetter(colIndex + 1))\(rowNumber)"
            switch cell {
            case .text(let value, let bold):
                guard !value.isEmpty else { continue }
                let styleAttr = bold ? " s=\"1\"" : ""
                sheetXML += "<c r=\"\(ref)\"\(styleAttr) t=\"inlineStr\"><is><t>\(XLSXCellPatch.xmlEscape(value))</t></is></c>"
            case .number(let value, let bold):
                let styleAttr = bold ? " s=\"1\"" : ""
                sheetXML += "<c r=\"\(ref)\"\(styleAttr)><v>\(value)</v></c>"
            }
        }
        sheetXML += "</row>\n"
    }
    sheetXML += "</sheetData></worksheet>"

    let archive = try Archive(url: url, accessMode: .create)
    let parts: [(String, String)] = [
        ("[Content_Types].xml", contentTypes),
        ("_rels/.rels", rootRels),
        ("xl/_rels/workbook.xml.rels", workbookRels),
        ("xl/workbook.xml", workbook),
        ("xl/styles.xml", styles),
        ("xl/worksheets/sheet1.xml", sheetXML)
    ]
    for (path, content) in parts {
        let data = Data(content.utf8)
        try archive.addEntry(
            with: path,
            type: .file,
            uncompressedSize: Int64(data.count),
            compressionMethod: .none
        ) { position, size in
            data.subdata(in: Int(position)..<(Int(position) + size))
        }
    }
}

/// 1-indexed column number to spreadsheet letter (1 -> A, 27 -> AA) — this
/// export needs up to 37 columns (Nr./Vorname/Nachname/Verein + 33 dates).
private func columnLetter(_ column: Int) -> String {
    var n = column
    var letters = ""
    while n > 0 {
        let remainder = (n - 1) % 26
        letters = String(UnicodeScalar(65 + remainder)!) + letters
        n = (n - 1) / 26
    }
    return letters
}
