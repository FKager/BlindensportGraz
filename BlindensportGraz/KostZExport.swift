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
/// other category, every BEILAGE column (including HONORARE/VERGÜTUNGEN's
/// own — attachment/receipt numbering is manual bookkeeping this app has no
/// data for), and ORT (no single canonical location for a month that can
/// span many trainings at different venues) are deliberately left blank for
/// the treasurer to fill by hand — same conservative "only fill what we
/// actually know" approach as PraeExporter.exportMainForm. I26's SUM(I10:I25)
/// formula is left untouched in the template XML and recalculates on open
/// once I15 has a value, same as how TeilnehmerlisteExporter/PraeExporter
/// never need to touch formula cells themselves.
enum KostZExporter {
    static func export(summary: KostZMonthSummary) throws -> URL {
        guard let templateURL = Bundle.main.url(forResource: "KostZ_Kostenzusammenstellung", withExtension: "xlsx") else {
            throw KostZExportError.templateNotFound
        }
        let sourceArchive = try Archive(url: templateURL, accessMode: .read)
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("KostZ-\(UUID().uuidString).xlsx")
        let outputArchive = try Archive(url: outputURL, accessMode: .create)

        let monthFormatter = DateFormatter()
        monthFormatter.locale = Locale(identifier: "de_AT")
        monthFormatter.dateFormat = "LLLL yyyy"
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "dd.MM.yyyy"
        let bounds = KostZCalculator.monthBounds(month: summary.month, year: summary.year)
        let betrifft = "Trainer:innen- und Helfer:innenhonorare \(monthFormatter.string(from: bounds.start))"

        for entry in sourceArchive {
            var data = Data()
            _ = try sourceArchive.extract(entry) { data.append($0) }

            if entry.path == "xl/worksheets/sheet1.xml", let xml = String(data: data, encoding: .utf8) {
                var patched = XLSXCellPatch.setText(in: xml, ref: "C3", value: betrifft)
                patched = XLSXCellPatch.setText(in: patched, ref: "D5", value: dateFormatter.string(from: bounds.start))
                patched = XLSXCellPatch.setText(in: patched, ref: "G5", value: dateFormatter.string(from: bounds.end))
                patched = XLSXCellPatch.setNumber(in: patched, ref: "I5", value: Double(bounds.dayCount))
                patched = XLSXCellPatch.setNumber(in: patched, ref: "E7", value: Double(summary.personCount))
                if summary.total > 0 {
                    patched = XLSXCellPatch.setNumber(in: patched, ref: "I15", value: summary.total)
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
