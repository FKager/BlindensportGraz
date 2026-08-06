import Foundation
import ZIPFoundation

/// Exports the Sport-Austria-federation-style "Trainingsfrequenzliste"
/// (training attendance register) — one row per team member, one column per
/// training date, "j"/"n" attendance per cell, plus a per-date total row.
///
/// Header layout reverse-engineered from the club's newer reference copy
/// (data/Trainingsfrequenzliste_Torball_2026.xlsx, an .xlsx this time, not
/// the older ÖBSV/OÖBSV .xls this exporter originally targeted): title row,
/// then "Verein/LV:"/"Sportart:"/"Sportstätte:" on one line, "Trainingszeiten:
/// Uhrzeit von:/bis:"/"Jahr:" on the next, then "Trainingstage (Datum):"
/// carrying the date columns directly in its own row, followed by a plain
/// Nr./Vorname/Nachname header row (no "Verein" column per row anymore — it's
/// stated once, club-wide, in the header). Field labels/values sit at fixed,
/// non-contiguous spreadsheet columns in that reference file (e.g.
/// "Sportart:" in M3 but its value in P3) rather than packed sequentially,
/// so — unlike the rest of this exporter's simple left-to-right rows — the
/// header rows below place cells by explicit column number.
///
/// Like before, this can't be built by patching a real template's XML
/// in-place (see XLSXCellPatch/TeilnehmerlisteExporter/PraeExporter for that
/// approach) since a from-scratch reproduction is simpler than diffing this
/// export's variable person/date row counts into a fixed template; follows
/// PraeExporter.exportDarstellung's precedent of building a fresh, minimal
/// .xlsx from scratch instead.
enum TrainingsfrequenzlisteExporter {
    static func export(summary: TrainingsfrequenzlisteSummary, vereinName: String = "Grazer VSC") throws -> URL {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "de_AT")
        dateFormatter.dateFormat = "dd.MM."

        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "de_AT")
        timeFormatter.dateFormat = "HH:mm"

        let dateColumnStart = 4 // column D — Nr./Vorname/Nachname occupy A–C

        var rows: [XLSXRow] = []
        rows.append([(1, .text("T R A I N I N G S F R E Q U E N Z L I S T E", bold: true))])
        rows.append([])
        rows.append([
            (1, .text("Verein/LV:", bold: true)), (4, .text(vereinName)),
            (13, .text("Sportart:", bold: true)), (16, .text(summary.sport)),
            (21, .text("Sportstätte:", bold: true)), (25, .text(summary.location))
        ])
        rows.append([
            (3, .text("Trainingszeiten:", bold: true)),
            (5, .text("Uhrzeit von:", bold: true)), (8, .text(summary.startTime.map { timeFormatter.string(from: $0) } ?? "")),
            (11, .text("bis:", bold: true)), (12, .text(summary.endTime.map { timeFormatter.string(from: $0) } ?? "")),
            (21, .text("Jahr:", bold: true)), (25, .number(Double(summary.year)))
        ])
        rows.append([])

        var trainingstageRow: XLSXRow = [(2, .text("Trainingstage (Datum):", bold: true))]
        trainingstageRow.append(contentsOf: summary.trainingDates.enumerated().map { index, date in
            (dateColumnStart + index, .text(dateFormatter.string(from: date), bold: true))
        })
        rows.append(trainingstageRow)

        rows.append([(1, .text("Nr.", bold: true)), (2, .text("Vorname", bold: true)), (3, .text("Nachname", bold: true))])

        for (index, person) in summary.people.enumerated() {
            let lastNameWithSuffix = person.roleSuffix.map { "\(person.lastName) (\($0))" } ?? person.lastName
            var row: XLSXRow = [(1, .text("\(index + 1).")), (2, .text(person.firstName)), (3, .text(lastNameWithSuffix))]
            row.append(contentsOf: summary.trainingDates.enumerated().map { index, date in
                (dateColumnStart + index, .text(person.attended(on: date) ? "j" : "n"))
            })
            rows.append(row)
        }

        var totalRow: XLSXRow = [(2, .text(" ")), (3, .text("ges. TL", bold: true))]
        totalRow.append(contentsOf: summary.trainingDates.enumerated().map { index, date in
            (dateColumnStart + index, .number(Double(summary.totalPresent(on: date))))
        })
        rows.append(totalRow)

        rows.append([(1, .text(" ")), (2, .text("Trainingstage (Datum) bei anwesenden SportlerInnen \"j\" sonst \"n\" eintragen"))])

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

/// One row as explicit (1-based column, cell) placements, rather than a
/// plain left-to-right array — the header rows above need to place labels
/// and values at fixed, non-contiguous columns (e.g. "Sportart:" in column
/// M with its value in column P) to match the reference template.
private typealias XLSXRow = [(column: Int, cell: XLSXGridCell)]

private func writeMinimalXLSX(rows: [XLSXRow], sheetName: String, to url: URL) throws {
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
        for (column, cell) in row.sorted(by: { $0.column < $1.column }) {
            let ref = "\(columnLetter(column))\(rowNumber)"
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
/// export needs up to 37 columns (Nr./Vorname/Nachname + 33 dates).
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
