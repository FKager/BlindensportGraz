import Foundation
import ZIPFoundation

/// Exports the Sport-Austria-federation-style "Trainingsfrequenzliste"
/// (training attendance register) by patching the club's real, already
/// completed reference document — bundled as `Trainingsfrequenzliste_Vorlage.xlsx`,
/// a copy of `data/Trainingsfrequenzliste_Torball_2026.xlsx` — rather than
/// generating a fresh .xlsx from scratch. Per explicit user request: use that
/// exact file as the basis, keep its original layout untouched, and only
/// replace the member list and the training dates. Same technique as
/// `TeilnehmerlisteExporter`/`PraeExporter`: unzip the template, patch known
/// cell coordinates in `xl/worksheets/sheet1.xml` via `XLSXCellPatch`, copy
/// every other zip entry (styles, theme, and — unlike those two exporters —
/// a real `xl/sharedStrings.xml` holding every static label) through
/// byte-for-byte.
///
/// Coordinates reverse-engineered directly from the bundled file's own XML
/// (an .xlsx is a plain zip of XML, `unzip -l`/inspect
/// `xl/worksheets/sheet1.xml`):
/// - Row 1: title (static, untouched).
/// - Row 3: "Verein/LV:" label / value at A3 (merged A3:C3) / D3 (merged
///   D3:J3); "Sportart:" / value at M3 (merged M3:O3) / P3 (merged P3:T3) —
///   patched from the representative Training's `title` (falling back to the
///   summary's `sport` when there's no training in the period to take a
///   title from); "Sportstätte:" / value at U3 (merged U3:X3) / Y3 (merged
///   Y3:AB3) — Y3 is patched from the representative Training's `location`,
///   same source as the Trainingszeiten fields below (H4/L4).
/// - Row 4: "Trainingszeiten:"/"Uhrzeit von:" labels at C4/E4, value at H4
///   (merged H4:J4); "bis:" label at K4, value at L4 (merged L4:O4);
///   "Jahr:" label at U4 (merged U4:X4), value at Y4 (merged Y4:AB4).
/// - Row 6: the 25 training-date columns directly, D6:AB6 — real Excel date
///   serial numbers (numFmtId 164 = "d/m"), NOT text, see `excelSerialDate`.
/// - Row 7: static Nr./Vorname/Nachname header.
/// - Rows 8–31: the 24 person rows — A/B/C (Nr./Vorname/Nachname) plus one
///   "j"/"n" cell per date column.
/// - Row 32: the "ges. TL" total row, a `COUNTIF(D8:D31,"j")` shared formula
///   per date column — left in place (Excel/Numbers recalculate on open),
///   only its cached `<v>` is refreshed here for non-recalculating
///   previewers (e.g. iOS QuickLook via ShareLink).
///
/// All static text (title, "Verein/LV:", "Nr.", "ges. TL", the footnote)
/// lives in the template's own `xl/sharedStrings.xml` and is never touched —
/// only cells this exporter actually writes get rewritten to `t="inlineStr"`,
/// per `XLSXCellPatch`'s `overwriteCell` family.
enum TrainingsfrequenzlisteExporter {
    enum ExportError: LocalizedError {
        case templateNotFound
        case invalidTemplateEncoding

        var errorDescription: String? {
            switch self {
            case .templateNotFound:
                return "Die Formularvorlage (Trainingsfrequenzliste_Vorlage.xlsx) wurde nicht gefunden."
            case .invalidTemplateEncoding:
                return "Die Formularvorlage konnte nicht gelesen werden."
            }
        }
    }

    // D..AB — matches TrainingsfrequenzlisteCalculator.maxDateColumns (25).
    private static let dateColumns = 4...28
    // Rows 8...31 — matches TrainingsfrequenzlisteCalculator.maxPersonRows (24).
    private static let personRowStart = 8

    static func export(summary: TrainingsfrequenzlisteSummary, vereinName: String = "Sektion Blindensport (GVSC)") throws -> URL {
        guard let templateURL = Bundle.main.url(forResource: "Trainingsfrequenzliste_Vorlage", withExtension: "xlsx") else {
            throw ExportError.templateNotFound
        }

        let sourceArchive = try Archive(url: templateURL, accessMode: .read)
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Trainingsfrequenzliste-\(UUID().uuidString).xlsx")
        let outputArchive = try Archive(url: outputURL, accessMode: .create)

        for entry in sourceArchive {
            var data = Data()
            _ = try sourceArchive.extract(entry) { data.append($0) }

            if entry.path == "xl/worksheets/sheet1.xml" {
                guard let xml = String(data: data, encoding: .utf8) else {
                    throw ExportError.invalidTemplateEncoding
                }
                data = Data(patch(xml: xml, summary: summary, vereinName: vereinName).utf8)
            }

            // .none (stored) matches TeilnehmerlisteExporter's established
            // convention for this exact technique — see its own doc comment.
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

    private static func patch(xml: String, summary: TrainingsfrequenzlisteSummary, vereinName: String) -> String {
        var result = xml

        result = XLSXCellPatch.setInlineText(in: result, ref: "D3", value: vereinName)
        let sportartValue = (summary.title?.isEmpty == false) ? summary.title! : summary.sport
        result = XLSXCellPatch.setInlineText(in: result, ref: "P3", value: sportartValue)
        if let location = summary.location, !location.isEmpty {
            result = XLSXCellPatch.setInlineText(in: result, ref: "Y3", value: location)
        } else {
            result = XLSXCellPatch.clearCell(in: result, ref: "Y3")
        }

        if let startTime = summary.startTime {
            result = XLSXCellPatch.setCellNumber(in: result, ref: "H4", value: excelTimeFraction(startTime))
        } else {
            result = XLSXCellPatch.clearCell(in: result, ref: "H4")
        }
        if let endTime = summary.endTime {
            result = XLSXCellPatch.setCellNumber(in: result, ref: "L4", value: excelTimeFraction(endTime))
        } else {
            result = XLSXCellPatch.clearCell(in: result, ref: "L4")
        }
        result = XLSXCellPatch.setCellNumber(in: result, ref: "Y4", value: Double(summary.year))

        for (offset, column) in dateColumns.enumerated() {
            let ref = "\(columnLetter(column))6"
            if offset < summary.trainingDates.count {
                result = XLSXCellPatch.setCellNumber(in: result, ref: ref, value: excelSerialDate(summary.trainingDates[offset]))
            } else {
                result = XLSXCellPatch.clearCell(in: result, ref: ref)
            }
        }

        for rowOffset in 0..<TrainingsfrequenzlisteCalculator.maxPersonRows {
            let row = personRowStart + rowOffset
            let person: TrainingsfrequenzlistePerson? = rowOffset < summary.people.count ? summary.people[rowOffset] : nil

            result = XLSXCellPatch.setInlineText(in: result, ref: "A\(row)", value: person != nil ? "\(rowOffset + 1)." : "")
            result = XLSXCellPatch.setInlineText(in: result, ref: "B\(row)", value: person?.firstName ?? "")
            let lastName = person.map { p in p.roleSuffix.map { suffix in "\(p.lastName) (\(suffix))" } ?? p.lastName } ?? ""
            result = XLSXCellPatch.setInlineText(in: result, ref: "C\(row)", value: lastName)

            for (offset, column) in dateColumns.enumerated() {
                let ref = "\(columnLetter(column))\(row)"
                guard let person, offset < summary.trainingDates.count else {
                    result = XLSXCellPatch.clearCell(in: result, ref: ref)
                    continue
                }
                result = XLSXCellPatch.setInlineText(in: result, ref: ref, value: person.attended(on: summary.trainingDates[offset]) ? "j" : "n")
            }
        }

        for (offset, column) in dateColumns.enumerated() {
            let ref = "\(columnLetter(column))32"
            let total = offset < summary.trainingDates.count ? summary.totalPresent(on: summary.trainingDates[offset]) : 0
            result = XLSXCellPatch.setFormulaCachedValue(in: result, ref: ref, value: Double(total))
        }

        return result
    }

    /// Whole days between the Excel/Lotus 1900 date-system epoch
    /// (1899-12-30 — not 1900-01-01, to account for Excel's historical leap
    /// year bug) and `date`'s start-of-day. Confirmed against the bundled
    /// template's own values: serial 46029 round-trips to 2026-01-07.
    static func excelSerialDate(_ date: Date, calendar: Calendar = .current) -> Double {
        var epochComponents = DateComponents()
        epochComponents.year = 1899
        epochComponents.month = 12
        epochComponents.day = 30
        guard let epoch = calendar.date(from: epochComponents) else { return 0 }
        let days = calendar.dateComponents([.day], from: epoch, to: calendar.startOfDay(for: date)).day ?? 0
        return Double(days)
    }

    /// Excel stores a time-of-day as a fraction of 24h (e.g. 17:30 ->
    /// 0.729166…), matching the template's own H4/L4 values.
    static func excelTimeFraction(_ date: Date, calendar: Calendar = .current) -> Double {
        let components = calendar.dateComponents([.hour, .minute, .second], from: date)
        let seconds = Double((components.hour ?? 0) * 3600 + (components.minute ?? 0) * 60 + (components.second ?? 0))
        return seconds / 86400
    }
}

/// 1-indexed column number to spreadsheet letter (4 -> D, 28 -> AB) — this
/// template's date columns span D..AB (25 columns).
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
