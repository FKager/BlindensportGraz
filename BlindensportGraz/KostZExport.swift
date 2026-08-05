import Foundation
import ZIPFoundation

enum KostZExportError: LocalizedError {
    case templateNotFound

    var errorDescription: String? {
        switch self {
        case .templateNotFound:
            return "Die Formularvorlage (KostZ_Kostenzusammenstellung.xlsx) wurde nicht gefunden."
        }
    }
}

/// Fills the Sport Austria "KostZ" (Kostenzusammenstellung) template,
/// downloaded from sportaustria.at — a general-purpose funding-accounting
/// cost summary with twelve category rows (Fahrtkosten, Nächtigungskosten,
/// ..., HONORARE/VERGÜTUNGEN, ..., Diverses), each with a BEILAGE
/// (attachment/receipt number) and BETRAG (amount) column, plus a live
/// SUM formula total (I26).
///
/// This app only ever has data for ONE of those twelve categories —
/// "HONORARE / VERGÜTUNGEN" (lfd. Nr. 6, row 15) — since that's the line
/// Sport Austria's own guidance uses for trainer/helper compensation, and
/// it's exactly what KostZCalculator sums from Attendance.praeAmount. Every
/// other category and every BEILAGE column (including HONORARE/VERGÜTUNGEN's
/// own — attachment/receipt numbering is manual bookkeeping this app has no
/// data for) are deliberately left blank for the treasurer to fill by hand —
/// same conservative "only fill what we actually know" approach as
/// PraeExporter.exportMainForm. ORT (H3) is filled with "Graz" on the
/// Training/month export, since Grazer VSC trainings are always there; the
/// tournament export instead uses that tournament's own `city` field (see
/// SportEvent.city in Models.swift — added specifically for this, since a
/// tournament can be anywhere, unlike a training). I26's SUM(I10:I25)
/// formula is left untouched in the template XML and recalculates on open
/// once I15 has a value, same as how TeilnehmerlisteExporter/PraeExporter
/// never need to touch formula cells themselves.
enum KostZExporter {
    static func export(summary: KostZMonthSummary) throws -> URL {
        let monthFormatter = DateFormatter()
        monthFormatter.locale = Locale(identifier: "de_AT")
        monthFormatter.dateFormat = "LLLL yyyy"
        let bounds = KostZCalculator.monthBounds(month: summary.month, year: summary.year)
        let betrifft = "Trainer:innen- und Helfer:innenhonorare \(monthFormatter.string(from: bounds.start))"
        // ZEITRAUM/TAGE come from the actual training dates in this month,
        // not the plain calendar bounds — a training only happens some days
        // of the month, so "1st to last calendar day, N calendar days"
        // overstated both. Falls back to the calendar month bounds (with a
        // 0 day count) only if no training was held that month at all.
        let periodStart = summary.trainingDates.first ?? bounds.start
        let periodEnd = summary.trainingDates.last ?? bounds.end
        return try export(betrifft: betrifft, periodStart: periodStart, periodEnd: periodEnd,
                           dayCount: summary.trainingDates.count, personCount: summary.personCount,
                           total: summary.total, ort: "Graz")
    }

    /// Same template, filled from a single tournament instead of a calendar
    /// month — ZEITRAUM becomes the tournament's own start/end dates (day
    /// count computed inclusively, same convention as monthBounds' dayCount)
    /// and BETRIFFT names the tournament instead of "<Month> <Year>". ORT
    /// comes from the tournament's own `city` — unlike a training, a
    /// tournament isn't always in Graz — left blank only if that field was
    /// never filled in.
    static func export(summary: KostZTournamentSummary) throws -> URL {
        let tournament = summary.tournament
        let betrifft = "Trainer:innen- und Helfer:innenhonorare \(tournament.title)"
        let calendar = Calendar.current
        let dayCount = (calendar.dateComponents([.day],
                                                  from: calendar.startOfDay(for: tournament.startDate),
                                                  to: calendar.startOfDay(for: tournament.endDate)).day ?? 0) + 1
        return try export(betrifft: betrifft, periodStart: tournament.startDate, periodEnd: tournament.endDate,
                           dayCount: max(dayCount, 1), personCount: summary.personCount, total: summary.total,
                           ort: tournament.city.isEmpty ? nil : tournament.city)
    }

    private static func export(betrifft: String, periodStart: Date, periodEnd: Date,
                                dayCount: Int, personCount: Int, total: Double, ort: String?) throws -> URL {
        guard let templateURL = Bundle.main.url(forResource: "KostZ_Kostenzusammenstellung", withExtension: "xlsx") else {
            throw KostZExportError.templateNotFound
        }
        let sourceArchive = try Archive(url: templateURL, accessMode: .read)
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("KostZ-\(UUID().uuidString).xlsx")
        let outputArchive = try Archive(url: outputURL, accessMode: .create)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "dd.MM.yyyy"

        for entry in sourceArchive {
            var data = Data()
            _ = try sourceArchive.extract(entry) { data.append($0) }

            if entry.path == "xl/worksheets/sheet1.xml", let xml = String(data: data, encoding: .utf8) {
                var patched = XLSXCellPatch.setText(in: xml, ref: "C3", value: betrifft)
                if let ort {
                    patched = XLSXCellPatch.setText(in: patched, ref: "H3", value: ort)
                }
                patched = XLSXCellPatch.setText(in: patched, ref: "D5", value: dateFormatter.string(from: periodStart))
                patched = XLSXCellPatch.setText(in: patched, ref: "G5", value: dateFormatter.string(from: periodEnd))
                patched = XLSXCellPatch.setNumber(in: patched, ref: "I5", value: Double(dayCount))
                patched = XLSXCellPatch.setNumber(in: patched, ref: "E7", value: Double(personCount))
                if total > 0 {
                    patched = XLSXCellPatch.setNumber(in: patched, ref: "I15", value: total)
                }
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
}
