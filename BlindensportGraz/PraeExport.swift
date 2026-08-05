import Foundation
import ZIPFoundation

enum PraeExportError: LocalizedError {
    case templateNotFound

    var errorDescription: String? {
        switch self {
        case .templateNotFound:
            return "Die Formularvorlage (PRAE_Formular.xlsx) wurde nicht gefunden."
        }
    }
}

/// Exports for the Sport Austria PRAE ("Pauschale Reiseaufwandsentschädigung")
/// paperwork — see PraeCalculation.swift for how the underlying day/amount
/// data is computed from this app's own Attendance records.
///
/// Two Sport Austria documents are involved, and they get very different
/// treatment here:
///
/// 1. "Aufzeichnung über Einsätze..." (the main, signed monthly form,
///    bundled as PRAE_Formular.xlsx) is a genuinely complex template: an
///    irregular 31-cell calendar-day grid spread across ~30 columns with
///    inconsistent row spans, plus ActiveX checkbox controls for role
///    selection and legal declarations that must be ticked by the recipient
///    in person (the form exists specifically to be hand-signed — full
///    automation was never the point). Reverse-engineering the exact
///    day-grid cell coordinates from the raw XML turned out ambiguous even
///    after careful analysis (see the day-30 case: its label cell doesn't
///    sit in the grid the other 30 do), and this app's data model doesn't
///    even store the SVNR/Geburtsdatum fields most of the form needs. Given
///    a wrong cell placement here means real money recorded against the
///    wrong calendar day on a compliance document, this only auto-fills the
///    two cells that are both unambiguous (confirmed blank, unmerged, single
///    wide input cells: D4, D7) AND backed by data we actually have (name,
///    address) — everything else (month/year, the day grid, checkboxes,
///    signature) is left for manual completion, using the in-app PRAE
///    calculation screen as the source to transcribe from.
/// 2. "Darstellung der Verwendungszwecke" (the funding-accounting appendix)
///    is a plain three-column table with no checkboxes and a fully regular
///    layout — safe to fill completely. Its only official copy is a legacy
///    .xls (binary OLE) file, which can't be patched the same way an .xlsx
///    (a zip of XML) can, so this builds a fresh, minimal but valid .xlsx
///    from scratch with the same header text and column layout instead of
///    patching the original binary.
enum PraeExporter {
    // MARK: - Darstellung der Verwendungszwecke (built fresh, no template)

    static func exportDarstellung(summary: PraeMonthSummary, vereinName: String = "Grazer VSC") throws -> URL {
        let monthFormatter = DateFormatter()
        monthFormatter.locale = Locale(identifier: "de_AT")
        monthFormatter.dateFormat = "LLLL yyyy"
        let monthLabel = monthFormatter.string(from: dateFor(month: summary.month, year: summary.year))
        return try exportDarstellung(person: summary.person, periodFieldLabel: "Monat und Jahr:", periodValue: monthLabel,
                                      entries: summary.entries, total: summary.total, vereinName: vereinName)
    }

    /// Same appendix, filled from a single tournament's deployment days
    /// instead of a calendar month — the "Monat und Jahr" field becomes
    /// "Turnier" naming the tournament, since a tournament isn't a month.
    static func exportDarstellung(summary: PraeTournamentSummary, vereinName: String = "Grazer VSC") throws -> URL {
        try exportDarstellung(person: summary.person, periodFieldLabel: "Turnier:", periodValue: summary.tournament.title,
                               entries: summary.entries, total: summary.total, vereinName: vereinName)
    }

    private static func exportDarstellung(person: PraeEligiblePerson, periodFieldLabel: String, periodValue: String,
                                           entries: [PraeDayEntry], total: Double, vereinName: String) throws -> URL {
        var rows: [[XLSXCell]] = []
        rows.append([.text("Darstellung der Verwendungszwecke von pauschalen Reiseaufwandsentschädigungen zur Abrechnung von Fördermitteln im Sport", bold: true)])
        rows.append([.text("Name des Vereins/Verbands:"), .text(vereinName)])
        rows.append([.text("Name des Empfängers / der Empfängerin:"), .text(person.displayName)])
        rows.append([.text(periodFieldLabel), .text(periodValue)])
        rows.append([])
        rows.append([.text("Kalendertag", bold: true), .text("Entschädigungshöhe", bold: true), .text("Verwendungszweck", bold: true)])
        for entry in entries {
            rows.append([.number(Double(entry.day)), .number(entry.amount), .text(entry.purpose)])
        }
        rows.append([.text("Gesamt:", bold: true), .number(total)])
        rows.append([])
        rows.append([.text("Der abrechnende Verein/Verband bestätigt die Richtigkeit und Vollständigkeit obiger Angaben.")])
        rows.append([.text("Gegenständliche Liste ist eine Beilage zum Formular \"Aufzeichnung über Einsätze und Bestätigung über den Erhalt von pauschalen Reiseaufwandsentschädigungen\" und dient ausschließlich zur Abrechnung von Fördermitteln im Sport.")])

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PRAE-Darstellung-\(UUID().uuidString).xlsx")
        try writeMinimalXLSX(rows: rows, sheetName: "Darstellung", to: outputURL)
        return outputURL
    }

    // MARK: - Main signed form (patches the bundled official template)

    /// Only fills the name (D4) and address (D7) cells — see the type-level
    /// doc comment for why the rest is deliberately left blank.
    static func exportMainForm(person: PraeEligiblePerson) throws -> URL {
        guard let templateURL = Bundle.main.url(forResource: "PRAE_Formular", withExtension: "xlsx") else {
            throw PraeExportError.templateNotFound
        }
        let sourceArchive = try Archive(url: templateURL, accessMode: .read)
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PRAE-Formular-\(UUID().uuidString).xlsx")
        let outputArchive = try Archive(url: outputURL, accessMode: .create)

        for entry in sourceArchive {
            var data = Data()
            _ = try sourceArchive.extract(entry) { data.append($0) }

            if entry.path == "xl/worksheets/sheet1.xml", let xml = String(data: data, encoding: .utf8) {
                var patched = XLSXCellPatch.setText(in: xml, ref: "D4", value: person.displayName)
                patched = XLSXCellPatch.setText(in: patched, ref: "D7", value: person.member?.fullAddress ?? "")
                data = Data(patched.utf8)
            }

            try outputArchive.addEntry(
                with: entry.path,
                type: entry.type,
                uncompressedSize: Int64(data.count),
                compressionMethod: .none
            ) { position, size in
                data.subdata(in: Int(position)..<(Int(position) + size))
            }
        }

        return outputURL
    }

    private static func dateFor(month: Int, year: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1
        return Calendar.current.date(from: components) ?? Date()
    }
}

// MARK: - Minimal from-scratch .xlsx writer (Darstellung has no .xlsx template to patch)

private enum XLSXCell {
    case text(String, bold: Bool = false)
    case number(Double, bold: Bool = false)
}

/// Builds the smallest set of OOXML parts Excel/Numbers/LibreOffice will
/// open without complaint: content types, root + workbook relationships,
/// workbook.xml, a minimal styles.xml (default + bold cell format), and one
/// worksheet. Text cells use inline strings (t="inlineStr"), matching
/// TeilnehmerlisteExporter's convention, so no sharedStrings.xml is needed.
private func writeMinimalXLSX(rows: [[XLSXCell]], sheetName: String, to url: URL) throws {
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

/// 1-indexed column number to spreadsheet letter (1 -> A, 27 -> AA). This
/// export never needs more than 3 columns, but the general form costs nothing.
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
