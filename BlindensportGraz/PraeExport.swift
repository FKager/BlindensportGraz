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
///    point), but the day grid ITSELF and the "im Monat:"/"Jahr:" header are
///    now auto-filled too (an earlier version of this comment claimed the
///    grid's coordinates were too ambiguous to patch — that turned out
///    wrong; `<mergeCells>` in the raw XML gives an exact, unambiguous
///    layout once actually dumped and read, see `dayGridAmountRef` below).
///    What's still genuinely left for manual completion is only what the
///    form exists to capture in person: the role/declaration checkboxes
///    (ActiveX controls) and the recipient's signature. The personal-data
///    header row IS fully auto-filled: name (D4), SVNR (D5), Geburtsdatum
///    (L5), address (D7), and IBAN (D33) are all confirmed-blank,
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
            patched = XLSXCellPatch.setText(in: patched, ref: "C3", value: person.praeFormName)
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

    /// The day-grid ("Einsatztage und Entschädigungshöhe") spans rows 12–15,
    /// 10 day-columns per row (days 1–10 on row 12, 11–20 on row 13, 21–30 on
    /// row 14, 31 alone on row 15) — found by dumping the template's own
    /// `<mergeCells>`, not guessed: each day's static label cell (`B12`,
    /// `E12`, `H12`, … stepping 3 columns apart) is immediately followed by a
    /// merged 2-column amount cell (`C12:D12`, `F12:G12`, …) — literally "one
    /// column after the day", confirming the user's own description of the
    /// layout. `dayGridAmountRef` derives the amount cell's top-left ref
    /// (the only cell of a merge that XLSXCellPatch needs to touch) purely
    /// from the day number, no per-day lookup table needed since the pattern
    /// is fully regular once the row split and 3-column step are known.
    private static func dayGridAmountRef(day: Int) -> String? {
        guard (1...31).contains(day) else { return nil }
        let row: Int
        let indexInRow: Int
        switch day {
        case 1...10: row = 12; indexInRow = day - 1
        case 11...20: row = 13; indexInRow = day - 11
        case 21...30: row = 14; indexInRow = day - 21
        default: row = 15; indexInRow = 0 // day 31, the row's only entry
        }
        // Label sits at column 2 + indexInRow*3 (B=2, E=5, H=8, …); the
        // amount's merged cell starts one column after that.
        let amountColumn = 2 + indexInRow * 3 + 1
        return "\(columnLetter(amountColumn))\(row)"
    }

    /// Fills name (D4), SVNR (D5), Geburtsdatum (L5), address (D7), IBAN
    /// (D33), the "im Monat:"/"Jahr:" header (B11/K11), the
    /// "Verwendungszweck:" value (T11 — the bare training name, same kind of
    /// value KostZ's C3 gets), every deployment day's amount in the day grid
    /// (see `dayGridAmountRef`), and the "Übungsleiter:in" role checkbox
    /// (see `uebungsleiterCheckboxShapeID`) — this club's trainings always
    /// use that role. Every OTHER role/declaration checkbox and the
    /// recipient's signature still stay manual (see the type-level doc
    /// comment).
    static func exportMainForm(summary: PraeMonthSummary) throws -> URL {
        try exportMainForm(person: summary.person, month: summary.month, year: summary.year,
                            entries: summary.entries, trainingName: summary.trainingName,
                            checkedRoleShapeID: uebungsleiterCheckboxShapeID)
    }

    /// Same main form, filled from a single tournament's deployment days.
    /// The form has no "Turnier:" alternative to "im Monat:"/"Jahr:" (unlike
    /// the Darstellung appendix's patchable period label) since it's a fixed
    /// official layout — filled with the tournament's own start month/year,
    /// which covers the common case of a tournament that doesn't straddle a
    /// month boundary; a multi-day tournament spanning two calendar months
    /// would still place every day's amount in the correct grid cell, just
    /// under one (the tournament's starting) month header. T11 is
    /// unambiguous here: the tournament's own bare title. Checks the
    /// "Trainer:in" role checkbox (`trainerCheckboxShapeID`, B9) instead of
    /// Training's "Übungsleiter:in" — this club's tournament deployments are
    /// always coaching, unlike trainings. Every other role/declaration
    /// checkbox stays manual.
    static func exportMainForm(summary: PraeTournamentSummary) throws -> URL {
        let components = Calendar.current.dateComponents([.month, .year], from: summary.tournament.startDate)
        return try exportMainForm(person: summary.person, month: components.month ?? 1, year: components.year ?? 0,
                                   entries: summary.entries, trainingName: summary.tournament.title,
                                   checkedRoleShapeID: trainerCheckboxShapeID)
    }

    /// The real template's role checkboxes — genuine Excel Form-control
    /// checkboxes (not ActiveX/OLE objects, confirmed by the template having
    /// plain `xl/ctrlProps/*.xml` + `xl/drawings/vmlDrawing1.vml` entries and
    /// no `activeX*.bin` blobs), each floating OVER its label cell rather
    /// than living IN it (found via each shape's `<x:Anchor>` in the VML —
    /// column/row pairs, 0-indexed). Neither has an `<x:FmlaLink>` to any
    /// cell, so "checking" one means inserting `<x:Checked>1</x:Checked>`
    /// into its own `<x:ClientData>` block — see `checkFormCheckbox`.
    /// `uebungsleiterCheckboxShapeID` anchors at column 15/row 8 (0-indexed)
    /// = cell **P9** ("Übungsleiter:in", shared string 74); `trainerCheckboxShapeID`
    /// anchors at column 1/row 8 = cell **B9** ("Trainer:in", shared string
    /// 72) — both row 9's role-checkbox row, confirmed against the real
    /// template's `vmlDrawing1.vml`. Every other role checkbox on this row
    /// (Sportler:in/A9, Lehrwart:in-Instruktor:in/H9, Masseur:in/X9, and row
    /// 10's Sportarzt-Sportärztin/Zeugwart:in/Schieds-Kampfrichter:in/
    /// Rennleiter:in) stays manual — this app only ever fills the ONE role
    /// checkbox that always applies for the export's own scope (Training vs
    /// Tournament).
    private static let uebungsleiterCheckboxShapeID = "Kontrollkästchen_x0020_17"
    private static let trainerCheckboxShapeID = "Kontrollkästchen_x0020_13"

    private static func exportMainForm(person: PraeEligiblePerson, month: Int, year: Int, entries: [PraeDayEntry],
                                        trainingName: String, checkedRoleShapeID: String?) throws -> URL {
        guard let templateURL = Bundle.main.url(forResource: "PRAE_Formular", withExtension: "xlsx") else {
            throw PraeExportError.templateNotFound
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "dd.MM.yyyy"
        let monthFormatter = DateFormatter()
        monthFormatter.locale = Locale(identifier: "de_AT")
        monthFormatter.dateFormat = "LLLL"

        return try patchTemplate(templateURL: templateURL, outputPrefix: "PRAE-Formular", vmlPatch: checkedRoleShapeID.map { shapeID in
            { vml in checkFormCheckbox(in: vml, shapeID: shapeID) }
        }) { xml in
            var patched = XLSXCellPatch.setText(in: xml, ref: "D4", value: person.praeFormName)
            patched = XLSXCellPatch.setText(in: patched, ref: "D5", value: person.member?.svnr ?? "")
            patched = XLSXCellPatch.setText(in: patched, ref: "D7", value: person.member?.fullAddress ?? "")
            if let birthDate = person.member?.birthDate {
                patched = XLSXCellPatch.setText(in: patched, ref: "L5", value: dateFormatter.string(from: birthDate))
            }
            if let iban = person.member?.iban, !iban.isEmpty {
                patched = XLSXCellPatch.setText(in: patched, ref: "D33", value: iban)
            }

            patched = XLSXCellPatch.setText(in: patched, ref: "B11", value: monthFormatter.string(from: dateFor(month: month, year: year)).capitalized)
            patched = XLSXCellPatch.setText(in: patched, ref: "K11", value: String(year))
            patched = XLSXCellPatch.setText(in: patched, ref: "T11", value: trainingName)

            for entry in entries {
                guard let ref = dayGridAmountRef(day: entry.day) else { continue }
                patched = XLSXCellPatch.setNumber(in: patched, ref: ref, value: entry.amount)
            }

            // L16 ("...in Höhe von:") already carries the template's own
            // SUM(day-grid) formula (=C12+C13+...+AD14) — Excel/Numbers
            // recalculate it on open regardless of what we write here, but
            // its cached <v> (currently 0, a pristine template's blank grid
            // sums to zero) needs refreshing too for non-recalculating
            // previewers, same reasoning as TrainingsfrequenzlisteExporter's
            // "ges. TL" row. B18 ("in Worten:") has no formula/template
            // support for spelling out a number, so it's written directly.
            let total = entries.reduce(0) { $0 + $1.amount }
            patched = XLSXCellPatch.setFormulaCachedValue(in: patched, ref: "L16", value: total)
            if total > 0 {
                patched = XLSXCellPatch.setText(in: patched, ref: "B18", value: GermanNumberWords.spelledOutEuroAmount(total))
            }

            return patched
        }
    }

    /// 1-indexed column number to spreadsheet letter (3 -> C, 30 -> AD) —
    /// same technique as TrainingsfrequenzlisteExporter's private helper of
    /// the same shape, not shared since it's a two-line function and the two
    /// exporters otherwise share nothing but XLSXCellPatch.
    private static func columnLetter(_ column: Int) -> String {
        var n = column
        var letters = ""
        while n > 0 {
            let remainder = (n - 1) % 26
            letters = String(UnicodeScalar(65 + remainder)!) + letters
            n = (n - 1) / 26
        }
        return letters
    }

    private static func dateFor(month: Int, year: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1
        return Calendar.current.date(from: components) ?? Date()
    }

    /// Shared unzip → patch `xl/worksheets/sheet1.xml` (and, when `vmlPatch`
    /// is given, `xl/drawings/vmlDrawing1.vml` too) → rezip pipeline used by
    /// both templates in this file — every other zip entry (styles, theme,
    /// control definitions, drawings) is copied through byte-for-byte.
    /// `vmlPatch` only applies to `PRAE_Formular.xlsx` (the only template
    /// with form checkboxes) — `exportDarstellung` never passes one, so its
    /// template's lack of a `vmlDrawing1.vml` entry is a no-op, not an error.
    private static func patchTemplate(templateURL: URL, outputPrefix: String,
                                       vmlPatch: ((String) -> String)? = nil,
                                       patch: (String) throws -> String) throws -> URL {
        let sourceArchive = try Archive(url: templateURL, accessMode: .read)
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(outputPrefix)-\(UUID().uuidString).xlsx")
        let outputArchive = try Archive(url: outputURL, accessMode: .create)

        for entry in sourceArchive {
            var data = Data()
            _ = try sourceArchive.extract(entry) { data.append($0) }

            if entry.path == "xl/worksheets/sheet1.xml", let xml = String(data: data, encoding: .utf8) {
                data = Data(try patch(xml).utf8)
            } else if entry.path == "xl/drawings/vmlDrawing1.vml", let vmlPatch, let vml = String(data: data, encoding: .utf8) {
                data = Data(vmlPatch(vml).utf8)
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

    /// Checks a real Excel Form-control checkbox that floats OVER a cell
    /// (positioned via its `<x:Anchor>`) rather than being tied to one via
    /// `<x:FmlaLink>` — inserting `<x:Checked>1</x:Checked>` right after its
    /// `<x:ClientData ObjectType="Checkbox">` opening tag is exactly what
    /// Excel itself writes when a user ticks the box by hand. Scoped to the
    /// one `<v:shape id="...">...</v:shape>` block matching `shapeID` first
    /// (every shape's `<x:ClientData ObjectType="Checkbox">` opening tag is
    /// byte-identical, so a plain string search without that scoping would
    /// check the WRONG box — whichever happens to come first in the file).
    private static func checkFormCheckbox(in vml: String, shapeID: String) -> String {
        let shapeStartMarker = "<v:shape id=\"\(shapeID)\""
        guard let shapeStart = vml.range(of: shapeStartMarker),
              let shapeEnd = vml.range(of: "</v:shape>", range: shapeStart.lowerBound..<vml.endIndex) else { return vml }
        let shapeRange = shapeStart.lowerBound..<shapeEnd.upperBound
        var shapeBlock = String(vml[shapeRange])
        guard let clientDataOpen = shapeBlock.range(of: "<x:ClientData ObjectType=\"Checkbox\">") else { return vml }
        shapeBlock.replaceSubrange(clientDataOpen, with: "<x:ClientData ObjectType=\"Checkbox\"><x:Checked>1</x:Checked>")
        return vml.replacingCharacters(in: shapeRange, with: shapeBlock)
    }
}

/// Spells out a Euro amount in German words, for the PRAE main form's
/// "in Worten:" (B18) field — e.g. 135.50 -> "Einhundertfünfunddreißig Euro
/// und fünfzig Cent". Uses the formal "ein-" prefixed style ("einhundert",
/// "eintausend") official Austrian documents use, not the colloquial
/// "hundert"/"tausend" short form. Only used by PraeExporter; kept top-level
/// (not nested) since it's a general-purpose number-to-words utility with no
/// PRAE-specific state, in case another export ever needs the same thing.
enum GermanNumberWords {
    private static let onesStandalone = ["null", "eins", "zwei", "drei", "vier", "fünf", "sechs", "sieben", "acht", "neun"]
    // Same digit words, but without the standalone "eins" -> used as a
    // prefix ("ein-und-zwanzig", "einhundert"), never on its own.
    private static let onesPrefix = ["", "ein", "zwei", "drei", "vier", "fünf", "sechs", "sieben", "acht", "neun"]
    private static let teens = ["zehn", "elf", "zwölf", "dreizehn", "vierzehn", "fünfzehn", "sechzehn", "siebzehn", "achtzehn", "neunzehn"]
    private static let tens = ["", "", "zwanzig", "dreißig", "vierzig", "fünfzig", "sechzig", "siebzig", "achtzig", "neunzig"]

    /// Spells out a non-negative integer below 1,000,000 — plenty of
    /// headroom for a PRAE total (legally capped at €720/month, though the
    /// cap is only flagged, not enforced, see PraeCalculator's doc comment).
    /// Falls back to plain digits above that rather than growing this into a
    /// general-purpose arbitrary-precision speller no caller needs.
    static func spellOut(_ n: Int) -> String {
        if n < 0 { return "minus " + spellOut(-n) }
        if n == 0 { return onesStandalone[0] }
        if n < 10 { return onesStandalone[n] }
        if n < 20 { return teens[n - 10] }
        if n < 100 {
            let (t, o) = (n / 10, n % 10)
            return o == 0 ? tens[t] : onesPrefix[o] + "und" + tens[t]
        }
        if n < 1000 {
            let (h, rest) = (n / 100, n % 100)
            let prefix = (h == 1 ? "ein" : onesStandalone[h]) + "hundert"
            return rest == 0 ? prefix : prefix + spellOut(rest)
        }
        if n < 1_000_000 {
            let (th, rest) = (n / 1000, n % 1000)
            let prefix = (th == 1 ? "ein" : spellOut(th)) + "tausend"
            return rest == 0 ? prefix : prefix + spellOut(rest)
        }
        return String(n)
    }

    /// Rounds to the nearest cent first (currency values shouldn't carry
    /// float noise like 45.499999999996 into a legal document), then spells
    /// out "<Euro> Euro und <Cent> Cent" — the "und <Cent> Cent" clause is
    /// dropped entirely for a whole-euro amount, matching how this phrase is
    /// conventionally written by hand.
    static func spelledOutEuroAmount(_ amount: Double) -> String {
        let totalCents = Int((amount * 100).rounded())
        let euros = totalCents / 100
        let cents = abs(totalCents % 100)
        let euroWords = spellOut(euros)
        let capitalized = euroWords.prefix(1).uppercased() + euroWords.dropFirst()
        let euroClause = "\(capitalized) Euro"
        guard cents != 0 else { return euroClause }
        return "\(euroClause) und \(spellOut(cents)) Cent"
    }
}
