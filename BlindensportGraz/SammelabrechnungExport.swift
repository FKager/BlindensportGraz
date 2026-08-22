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
    /// One calendar month's collective settlement — KostZ across every
    /// Training that month, plus PRAE-Formular + PRAE-Darstellung for every
    /// coach/assistant with a non-zero honorarium that month.
    static func export(kostZ: KostZMonthSummary, praeSummaries: [PraeMonthSummary]) throws -> URL {
        let kostZURL = try KostZExporter.export(summary: kostZ)
        var praeFiles: [(name: String, url: URL)] = []
        for summary in praeSummaries {
            praeFiles.append((fileName(for: summary.person, suffix: "PRAE"), try PraeExporter.exportMainForm(summary: summary)))
            if !summary.entries.isEmpty {
                praeFiles.append((fileName(for: summary.person, suffix: "PRAE-Darstellung"), try PraeExporter.exportDarstellung(summary: summary)))
            }
        }
        return try zip(kostZURL: kostZURL, praeFiles: praeFiles)
    }

    /// Same bundle, scoped to a single tournament instead of a calendar
    /// month — mirrors KostZExporter/PraeExporter's own month-vs-tournament
    /// overload split.
    static func export(kostZ: KostZTournamentSummary, praeSummaries: [PraeTournamentSummary]) throws -> URL {
        let kostZURL = try KostZExporter.export(summary: kostZ)
        var praeFiles: [(name: String, url: URL)] = []
        for summary in praeSummaries {
            praeFiles.append((fileName(for: summary.person, suffix: "PRAE"), try PraeExporter.exportMainForm(summary: summary)))
            if !summary.entries.isEmpty {
                praeFiles.append((fileName(for: summary.person, suffix: "PRAE-Darstellung"), try PraeExporter.exportDarstellung(summary: summary)))
            }
        }
        return try zip(kostZURL: kostZURL, praeFiles: praeFiles)
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
        var files: [(name: String, url: URL)] = []

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

        let tournamentsInYear = tournaments.filter { Calendar.current.component(.year, from: $0.startDate) == year }
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

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Sammelabrechnung-Saison-\(year)-\(UUID().uuidString).zip")
        let archive = try Archive(url: outputURL, accessMode: .create)
        for file in files {
            try addFile(at: file.url, as: file.name, to: archive)
        }
        return outputURL
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
    /// first) containing the KostZ file plus every PRAE file, each read
    /// whole into memory and re-added as its own entry. `.none` (stored),
    /// not `.deflate`, matching every other exporter's compressionMethod
    /// choice in this codebase — each member is already a compressed .xlsx,
    /// so deflating the outer zip again buys negligible size for the extra
    /// complexity/risk.
    private static func zip(kostZURL: URL, praeFiles: [(name: String, url: URL)]) throws -> URL {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Sammelabrechnung-\(UUID().uuidString).zip")
        let archive = try Archive(url: outputURL, accessMode: .create)

        try addFile(at: kostZURL, as: "KostZ.xlsx", to: archive)
        for file in praeFiles {
            try addFile(at: file.url, as: file.name, to: archive)
        }

        return outputURL
    }

    private static func addFile(at fileURL: URL, as entryName: String, to archive: Archive) throws {
        let data = try Data(contentsOf: fileURL)
        try archive.addEntry(with: entryName, type: .file, uncompressedSize: Int64(data.count), compressionMethod: .none) { position, size in
            data.subdata(in: Int(position)..<(Int(position) + size))
        }
    }
}
