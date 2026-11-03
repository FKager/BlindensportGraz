import Foundation
import SwiftData
import ZIPFoundation

/// Bundles one accounting period's full PRAE/KostZ paperwork into a single
/// .zip — the "Sammelabrechnung" (collective settlement) a treasurer files
/// all at once, per user request ("Add a Sammelabrechnung inside Berichte.
/// This should include all PRAE, PRAE Darstellung of the helper/trainer and
/// KostZ for a tournament or training period. The excel files should be
/// zipped together."). Pure orchestration — every individual .xlsx is still
/// produced by the existing, already-tested exporters
/// (KostZExporter/PraeExporter); this type only calls them once per eligible
/// person and re-zips their outputs together, the same way
/// TrainingsfrequenzlisteExporter/TeilnehmerlisteExporter/PraeExporter
/// already unzip→patch→rezip a single template, just one level up (zip of
/// already-valid .xlsx files instead of zip of XML parts).
///
/// "Eligible person" here means whoever KostZCalculator's summary already
/// resolved to a non-zero honorarium for the period (`personAmounts`, amount
/// > 0 only) — the same people the KostZ total is built from, so there's no
/// separate eligibility computation to keep in sync. A person's Darstellung
/// file is only included when they actually have deployment-day entries
/// (always true here, since `personAmounts` already filtered to amount > 0),
/// matching PraeCalculationView's own `!summary.entries.isEmpty` gate on
/// showing that ShareLink.
enum SammelabrechnungExporter {
    /// One produced report: its file name inside the bundle and the .xlsx.
    typealias ReportFile = (name: String, url: URL)

    /// An uploaded document bundled as-is (the tournament's Einladung).
    struct Attachment: Sendable, Equatable {
        var fileName: String
        var data: Data

        /// "Einladung_<title>.<ext>", "/" stripped like the other entry names.
        static func invitation(_ invitation: TournamentInvitation, tournamentTitle: String) -> Attachment {
            let title = tournamentTitle.replacingOccurrences(of: "/", with: "-")
            let base = title.isEmpty ? "Einladung" : "Einladung_\(title)"
            return Attachment(fileName: "\(base).\(invitation.fileExtension)", data: invitation.fileData)
        }
    }

    /// One calendar month's collective settlement — KostZ across every
    /// Training that month, plus PRAE-Formular + PRAE-Darstellung for every
    /// coach/assistant with a non-zero honorarium that month. `kostZ` is
    /// optional (nil = excluded) so it follows the same "presence/selection
    /// = inclusion" convention as the tournament overload below — `kostZ:
    /// nil` when SammelabrechnungView's KostZ toggle is off, `praeSummaries`
    /// already filtered to only the helpers selected in its per-helper PRAE
    /// list.
    static func export(kostZ: KostZMonthSummary?, praeSummaries: [PraeMonthSummary]) throws -> URL {
        try zipFiles(files(kostZ: kostZ, praeSummaries: praeSummaries), namePrefix: "Sammelabrechnung")
    }

    /// The month bundle's files, unzipped (zip or print them).
    static func files(kostZ: KostZMonthSummary?, praeSummaries: [PraeMonthSummary]) throws -> [ReportFile] {
        var files: [ReportFile] = []
        if let kostZ {
            files.append(("KostZ.xlsx", try KostZExporter.export(summary: kostZ)))
        }
        for summary in praeSummaries {
            files.append((fileName(for: summary.person, suffix: "PRAE"), try PraeExporter.exportMainForm(summary: summary)))
            if !summary.entries.isEmpty {
                files.append((fileName(for: summary.person, suffix: "PRAE-Darstellung"), try PraeExporter.exportDarstellung(summary: summary)))
            }
        }
        return files
    }

    /// Same bundle, scoped to a single tournament instead of a calendar
    /// month — mirrors KostZExporter/PraeExporter's own month-vs-tournament
    /// overload split. Unlike the month overload above, every part here is
    /// independently optional (`kostZ`/the two `TeilnehmerlisteContext`
    /// params are nil, or `praeSummaries` is empty, to leave that part out)
    /// — SammelabrechnungTournamentView's four "Enthaltene Teile" toggles
    /// (all on by default) map straight onto these, so unchecking one just
    /// omits that file rather than the exporter needing its own separate
    /// include flags. The two Teilnehmerliste files mirror
    /// TournamentDetailView's existing "Teilnehmer Sportler"/"Teilnehmer
    /// Helfer" Berichte entries (same role split, same TN-Sportler/TN-Helfer
    /// naming) — just bundled in here too instead of exported one at a time.
    static func export(kostZ: KostZTournamentSummary?, praeSummaries: [PraeTournamentSummary],
                        teilnehmerlisteSportler: TeilnehmerlisteContext? = nil,
                        teilnehmerlisteHelfer: TeilnehmerlisteContext? = nil,
                        invitation: Attachment? = nil) throws -> URL {
        try zipFiles(files(kostZ: kostZ, praeSummaries: praeSummaries,
                           teilnehmerlisteSportler: teilnehmerlisteSportler,
                           teilnehmerlisteHelfer: teilnehmerlisteHelfer,
                           invitation: invitation),
                     namePrefix: "Sammelabrechnung")
    }

    /// The tournament bundle's files, unzipped (zip or print them).
    static func files(kostZ: KostZTournamentSummary?, praeSummaries: [PraeTournamentSummary],
                      teilnehmerlisteSportler: TeilnehmerlisteContext? = nil,
                      teilnehmerlisteHelfer: TeilnehmerlisteContext? = nil,
                      invitation: Attachment? = nil) throws -> [ReportFile] {
        var files: [ReportFile] = []
        if let invitation {
            files.append((invitation.fileName, try write(invitation)))
        }
        if let kostZ {
            files.append(("KostZ.xlsx", try KostZExporter.export(summary: kostZ)))
        }
        for summary in praeSummaries {
            files.append((fileName(for: summary.person, suffix: "PRAE"), try PraeExporter.exportMainForm(summary: summary)))
            if !summary.entries.isEmpty {
                files.append((fileName(for: summary.person, suffix: "PRAE-Darstellung"), try PraeExporter.exportDarstellung(summary: summary)))
            }
        }
        if let teilnehmerlisteSportler {
            files.append(("TeilnehmerInnenliste-Sportler.xlsx", try TeilnehmerlisteExporter.export(context: teilnehmerlisteSportler)))
        }
        if let teilnehmerlisteHelfer {
            files.append(("TeilnehmerInnenliste-Helfer.xlsx", try TeilnehmerlisteExporter.export(context: teilnehmerlisteHelfer)))
        }
        return files
    }

    /// Full-season rollup (audit.md Enhancement #8) — every calendar month's
    /// and every tournament's KostZ+PRAE bundle, plus every training sport's
    /// two Trainingsfrequenzliste half-years, all for one year, flattened
    /// into a single zip with period-prefixed file names so nothing
    /// collides. Pure orchestration over the existing per-period
    /// exporters (`KostZExporter`/`PraeExporter`/`TrainingsfrequenzlisteExporter`)
    /// — no new XLSX-patching logic, same as the two `export` overloads
    /// above. A month/tournament with zero eligible people (`personAmounts`
    /// empty) is skipped entirely, same as a sport/half-year with zero
    /// training dates — a season where nothing happened all year correctly
    /// produces a valid, empty (zero-entry) zip rather than 12 near-empty
    /// KostZ sheets or crashing.
    static func exportSeason(year: Int, allMemberships: [TeamMembership], tournaments: [Tournament],
                              sports: [String], in context: ModelContext) throws -> URL {
        try zipFiles(seasonFiles(year: year, allMemberships: allMemberships, tournaments: tournaments,
                                 sports: sports, in: context),
                     namePrefix: "Sammelabrechnung-Saison-\(year)")
    }

    /// The season rollup's files, unzipped (zip or print them).
    static func seasonFiles(year: Int, allMemberships: [TeamMembership], tournaments: [Tournament],
                            sports: [String], in context: ModelContext) throws -> [ReportFile] {
        var files: [ReportFile] = []

        for month in 1...12 {
            let kostZSummary = KostZCalculator.summary(month: month, year: year, allMemberships: allMemberships, in: context)
            guard !kostZSummary.personAmounts.isEmpty else { continue }
            let label = String(format: "%02d-%d", month, year)
            files.append(("\(label)_KostZ.xlsx", try KostZExporter.export(summary: kostZSummary)))
            for personAmount in kostZSummary.personAmounts {
                let praeSummary = PraeCalculator.summary(for: personAmount.person, month: month, year: year, in: context)
                files.append(("\(label)_\(fileName(for: praeSummary.person, suffix: "PRAE"))", try PraeExporter.exportMainForm(summary: praeSummary)))
                if !praeSummary.entries.isEmpty {
                    files.append(("\(label)_\(fileName(for: praeSummary.person, suffix: "PRAE-Darstellung"))", try PraeExporter.exportDarstellung(summary: praeSummary)))
                }
            }
        }

        let tournamentsInYear = tournaments
            .filter { Calendar.current.component(.year, from: $0.startDate) == year }
            .sorted { $0.startDate < $1.startDate }
        for tournament in tournamentsInYear {
            let kostZSummary = KostZCalculator.summary(for: tournament, allMemberships: allMemberships)
            guard !kostZSummary.personAmounts.isEmpty else { continue }
            let label = "Turnier_\(sanitize(tournament.title))"
            files.append(("\(label)_KostZ.xlsx", try KostZExporter.export(summary: kostZSummary)))
            for personAmount in kostZSummary.personAmounts {
                let praeSummary = PraeCalculator.summary(for: personAmount.person, tournament: tournament)
                files.append(("\(label)_\(fileName(for: praeSummary.person, suffix: "PRAE"))", try PraeExporter.exportMainForm(summary: praeSummary)))
                if !praeSummary.entries.isEmpty {
                    files.append(("\(label)_\(fileName(for: praeSummary.person, suffix: "PRAE-Darstellung"))", try PraeExporter.exportDarstellung(summary: praeSummary)))
                }
            }
        }

        for sport in sports {
            for halfYear in HalfYear.allCases {
                let summary = TrainingsfrequenzlisteCalculator.summary(sport: sport, halfYear: halfYear, year: year, in: context)
                guard !summary.trainingDates.isEmpty else { continue }
                let label = "\(sanitize(sport))_H\(halfYear.rawValue)-\(year)"
                files.append(("\(label)_Trainingsfrequenzliste.xlsx", try TrainingsfrequenzlisteExporter.export(summary: summary)))
            }
        }

        return files
    }

    /// Same "/" stripping as `fileName(for:suffix:)`, for the tournament-title
    /// and sport-name components of a season file's prefix.
    private static func sanitize(_ raw: String) -> String {
        raw.replacingOccurrences(of: "/", with: "-")
    }

    /// "Nachname_Vorname" (matches this app's established lastName-first
    /// sort/display convention, see Models.swift's `sortedByLastName`),
    /// falling back to `displayName` for a `PraeEligiblePerson` built without
    /// separate name parts (some existing test fixtures only set
    /// displayName) — either way, "/" is stripped since it isn't a valid zip
    /// entry-name path separator substitute here.
    private static func fileName(for person: PraeEligiblePerson, suffix: String) -> String {
        let name = [person.lastName, person.firstName].filter { !$0.isEmpty }.joined(separator: "_")
        let safeName = (name.isEmpty ? person.displayName : name).replacingOccurrences(of: "/", with: "-")
        return "\(suffix)_\(safeName).xlsx"
    }

    /// Creates a fresh .zip (not a patched template — nothing to unzip
    /// first) from an arbitrary flat list of already-produced files, each
    /// read whole into memory and re-added as its own entry. `.none`
    /// (stored), not `.deflate`, matching every other exporter's
    /// compressionMethod choice in this codebase — each member is already a
    /// compressed .xlsx, so deflating the outer zip again buys negligible
    /// size for the extra complexity/risk. Shared by every `export`/
    /// `exportSeason` overload above, each of which builds its own
    /// variable-length/variable-part file list first (KostZ/Teilnehmerliste
    /// entries optional, any number of per-person PRAE entries).
    private static func zipFiles(_ files: [ReportFile], namePrefix: String) throws -> URL {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(namePrefix)-\(UUID().uuidString).zip")
        let archive = try Archive(url: outputURL, accessMode: .create)
        for file in files {
            try addFile(at: file.url, as: file.name, to: archive)
        }
        return outputURL
    }

    /// Writes an uploaded document (the tournament invitation) to its own
    /// temp folder under its file name — the extension matters for printing
    /// (ReportPrinter picks PDF vs. web rendering by it).
    private static func write(_ attachment: Attachment) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(attachment.fileName)
        try attachment.data.write(to: url)
        return url
    }

    private static func addFile(at fileURL: URL, as entryName: String, to archive: Archive) throws {
        let data = try Data(contentsOf: fileURL)
        try archive.addEntry(with: entryName, type: .file, uncompressedSize: Int64(data.count), compressionMethod: .none) { position, size in
            data.subdata(in: Int(position)..<(Int(position) + size))
        }
    }
}
