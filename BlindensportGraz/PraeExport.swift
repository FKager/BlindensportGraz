import Foundation
import ZIPFoundation

enum PraeExportError: LocalizedError {
    case templateNotFound

    var errorDescription: String? {
        switch self {
        case .templateNotFound:
            return "Die Formularvorlage wurde nicht gefunden."
        }
    }
}

/// Exports for the Sport Austria PRAE ("Pauschale Reiseaufwandsentschädigung")
/// paperwork — see PraeCalculation.swift for how the underlying day/amount
/// data is computed from this app's own Attendance records.
///
/// Two Sport Austria documents are involved, both now patched from real,
/// web-sourced templates (same technique as TeilnehmerlisteExporter/
/// TrainingsfrequenzlisteExporter — unzip, patch known cell coordinates in
/// `xl/worksheets/sheet1.xml`, copy every other zip entry through
/// byte-for-byte):
///
/// 1. "Aufzeichnung über Einsätze..." (the main, signed monthly form,
///    bundled as PRAE_Formular.xlsx — confirmed byte-identical, via md5, to
///    the current official
///    `sportaustria.at/.../2023/Formular_Pauschale_Reiseaufwandsentschaedigung.xlsx`)
///    is a genuinely complex template: an irregular 31-cell calendar-day
///    grid spread across ~30 columns with inconsistent row spans, plus
///    ActiveX checkbox controls for role selection and legal declarations
///    that must be ticked by the recipient in person (the form exists
///    specifically to be hand-signed — full automation was never the
///    point). Reverse-engineering the exact day-grid cell coordinates from
///    the raw XML turned out ambiguous even after careful analysis (see the
///    day-30 case: its label cell doesn't sit in the grid the other 30 do),
///    so that part is still left for manual completion (month/year, the day
///    grid, checkboxes, signature), using the in-app PRAE calculation
///    screen as the source to transcribe from. The personal-data header row
///    IS fully auto-filled though: name (D4), SVNR (D5), Geburtsdatum (L5),
///    address (D7), and IBAN (D33) are all confirmed-blank,
///    unmerged-from-their-label, single wide input cells (verified against
///    the template's own merge/style XML, same scrutiny as the day-grid
///    check above) and all backed by `Member` fields this app already
///    stores — Member.svnr/birthDate/iban, sourced via `person.member`. A
///    person backed only by a `User` account (no `Member` roster entry) has
///    `person.member == nil`, so those fields export blank — same existing
///    behavior as the address field always had.
/// 2. "Darstellung der Verwendungszwecke" (the funding-accounting appendix)
///    was, until now, built from scratch — its only official copy on
///    sportaustria.at is a legacy .xls (binary OLE) file, which can't be
///    zip-patched the same way an .xlsx can. Per explicit user request to
///    use the real web-sourced file as the basis (same as
///    TrainingsfrequenzlisteExporter), it's now bundled as
///    `PRAE_Darstellung_Vorlage.xlsx` — a faithful **format conversion**
///    (not a re-design) of the real
///    `sportaustria.at/.../2020/PRAE_Darstellung_der_Verwendungszwecke.xls`,
///    reverse-engineered cell-by-cell (values/merges/borders/number formats)
///    with `xlrd` and rebuilt as a real, patchable .xlsx with `openpyxl` —
///    every label, merge, and the day-grid's cell layout matches the
///    original .xls exactly; only the file *format* changed, not its
///    content or layout. **This uncovered a real content mismatch**: the
///    from-scratch version this replaced also printed Wohnanschrift/
///    Sozialversicherungsnummer/IBAN rows (added earlier, before any real
///    template was available to check against) — the authentic form has
///    none of those, only Verein/Empfänger-Name/Geburtsdatum/Monat-Jahr.
///    Confirmed with the user (2026-08-06) to drop those three and match
///    the real form exactly, same as the day-grid's hard 21-row cap (the
///    real form only has 21 entry rows, not one per calendar day) and the
///    real form's complete lack of a "Gesamt" total row (the treasurer sums
///    by hand — no SUM formula exists in the original either, unlike
///    KostZExporter's I26).
enum PraeExporter {
    // MARK: - Darstellung der Verwendungszwecke (patches PRAE_Darstellung_Vorlage.xlsx)

    /// The real template's row 5 label cell (A5, merged A5:B5) is left blank
    /// on purpose — unlike every other static label in the form, this one
    /// needs to say "Monat und Jahr:" for a monthly export or "Turnier:"
    /// for a tournament export, so both the label AND its value (C5) are
    /// patched here rather than only the value.
    private static let periodLabelRef = "A5"
    private static let periodValueRef = "C5"

    /// Rows 8–28 in the real template — a hard cap inherited from the
    /// original paper form, same shape as TeilnehmerlisteExporter.maxRows/
    /// TrainingsfrequenzlisteCalculator.maxPersonRows.
    static let maxEntryRows = 21
    private static let firstEntryRow = 8

    static func exportDarstellung(summary: PraeMonthSummary, vereinName: String = "Grazer VSC") throws -> URL {
        let monthFormatter = DateFormatter()
        monthFormatter.locale = Locale(identifier: "de_AT")
        monthFormatter.dateFormat = "LLLL yyyy"
        let monthLabel = monthFormatter.string(from: dateFor(month: summary.month, year: summary.year))
        return try exportDarstellung(person: summary.person, periodFieldLabel: "Monat und Jahr:", periodValue: monthLabel,
                                      entries: summary.entries, vereinName: vereinName)
    }

    /// Same appendix, filled from a single tournament's deployment days
    /// instead of a calendar month — the "Monat und Jahr" field becomes
    /// "Turnier" naming the tournament, since a tournament isn't a month.
    static func exportDarstellung(summary: PraeTournamentSummary, vereinName: String = "Grazer VSC") throws -> URL {
        try exportDarstellung(person: summary.person, periodFieldLabel: "Turnier:", periodValue: summary.tournament.title,
                               entries: summary.entries, vereinName: vereinName)
    }

    private static func exportDarstellung(person: PraeEligiblePerson, periodFieldLabel: String, periodValue: String,
                                           entries: [PraeDayEntry], vereinName: String) throws -> URL {
        guard let templateURL = Bundle.main.url(forResource: "PRAE_Darstellung_Vorlage", withExtension: "xlsx") else {
            throw PraeExportError.templateNotFound
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "dd.MM.yyyy"

        return try patchTemplate(templateURL: templateURL, outputPrefix: "PRAE-Darstellung") { xml in
            var patched = XLSXCellPatch.setText(in: xml, ref: "C2", value: vereinName)
            patched = XLSXCellPatch.setText(in: patched, ref: "C3", value: person.displayName)
            if let birthDate = person.member?.birthDate {
                patched = XLSXCellPatch.setText(in: patched, ref: "C4", value: dateFormatter.string(from: birthDate))
            }
            patched = XLSXCellPatch.setText(in: patched, ref: periodLabelRef, value: periodFieldLabel)
            patched = XLSXCellPatch.setText(in: patched, ref: periodValueRef, value: periodValue)

            for (index, entry) in entries.prefix(maxEntryRows).enumerated() {
                let row = firstEntryRow + index
                patched = XLSXCellPatch.setNumber(in: patched, ref: "A\(row)", value: Double(entry.day))
                patched = XLSXCellPatch.setNumber(in: patched, ref: "B\(row)", value: entry.amount)
                patched = XLSXCellPatch.setText(in: patched, ref: "C\(row)", value: entry.purpose)
            }
            return patched
        }
    }

    // MARK: - Main signed form (patches the bundled official template)

    /// Fills name (D4), SVNR (D5), Geburtsdatum (L5), address (D7), and IBAN
    /// (D33) — see the type-level doc comment for why the day grid,
    /// checkboxes, and signature stay manual.
    static func exportMainForm(person: PraeEligiblePerson) throws -> URL {
        guard let templateURL = Bundle.main.url(forResource: "PRAE_Formular", withExtension: "xlsx") else {
            throw PraeExportError.templateNotFound
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "dd.MM.yyyy"

        return try patchTemplate(templateURL: templateURL, outputPrefix: "PRAE-Formular") { xml in
            var patched = XLSXCellPatch.setText(in: xml, ref: "D4", value: person.displayName)
            patched = XLSXCellPatch.setText(in: patched, ref: "D5", value: person.member?.svnr ?? "")
            patched = XLSXCellPatch.setText(in: patched, ref: "D7", value: person.member?.fullAddress ?? "")
            if let birthDate = person.member?.birthDate {
                patched = XLSXCellPatch.setText(in: patched, ref: "L5", value: dateFormatter.string(from: birthDate))
            }
            if let iban = person.member?.iban, !iban.isEmpty {
                patched = XLSXCellPatch.setText(in: patched, ref: "D33", value: iban)
            }
            return patched
        }
    }

    private static func dateFor(month: Int, year: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1
        return Calendar.current.date(from: components) ?? Date()
    }

    /// Shared unzip → patch `xl/worksheets/sheet1.xml` → rezip pipeline used
    /// by both templates in this file — every other zip entry (styles,
    /// theme, ActiveX controls, drawings) is copied through byte-for-byte.
    private static func patchTemplate(templateURL: URL, outputPrefix: String, patch: (String) throws -> String) throws -> URL {
        let sourceArchive = try Archive(url: templateURL, accessMode: .read)
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(outputPrefix)-\(UUID().uuidString).xlsx")
        let outputArchive = try Archive(url: outputURL, accessMode: .create)

        for entry in sourceArchive {
            var data = Data()
            _ = try sourceArchive.extract(entry) { data.append($0) }

            if entry.path == "xl/worksheets/sheet1.xml", let xml = String(data: data, encoding: .utf8) {
                data = Data(try patch(xml).utf8)
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
}
