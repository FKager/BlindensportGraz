import Foundation
import SwiftData

/// JSON shape for one Training export/import row. Field names mirror
/// `Training`'s own stored properties (via its `SportEvent` base). `teams`
/// is a plain array of team names (not ids) — mirrors `TeamImportExport`'s
/// own `TeamMembershipIO` precedent of referencing people/teams by
/// human-readable identity rather than requiring ids to round-trip out of
/// band first, so a training export stays usable standalone. `startDate` is
/// a plain ISO8601 string (not a native JSON date), same convention as
/// `MemberIO`'s date fields.
struct TrainingIO: Codable {
    var id: String?
    var title: String?
    var sport: String?
    var location: String?
    var street: String?
    var zip: String?
    var city: String?
    var country: String?
    var startDate: String?
    var durationMinutes: Int?
    var focusArea: String?
    var notes: String?
    var teams: [String]?
}

enum TrainingImportExport {
    private static let isoFormatter = ISO8601DateFormatter()

    // MARK: - Export

    /// Encodes the given trainings to pretty-printed, sorted-key JSON and
    /// writes it to a fresh temp file, ready for `ShareLink` — same
    /// eager-generation convention as `MemberImportExport.exportFile`.
    static func exportFile(trainings: [Training]) throws -> URL {
        let data = try encodedJSON(for: trainings)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("grazer-vsc-trainings-\(dateStamp()).json")
        try data.write(to: url, options: .atomic)
        return url
    }

    static func encodedJSON(for trainings: [Training]) throws -> Data {
        let rows = trainings
            .sorted { $0.startDate < $1.startDate }
            .map { training in
                TrainingIO(
                    id: training.id.uuidString,
                    title: training.title,
                    sport: training.sport,
                    location: training.location,
                    street: training.street,
                    zip: training.zip,
                    city: training.city,
                    country: training.country,
                    startDate: isoFormatter.string(from: training.startDate),
                    durationMinutes: training.durationMinutes,
                    focusArea: training.focusArea,
                    notes: training.notes,
                    teams: training.teams.map(\.name).sorted()
                )
            }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(rows)
    }

    private static func dateStamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: Date())
    }

    // MARK: - Import

    struct ImportResult {
        var created = 0
        var updated = 0
        var skipped = 0
        var skippedDetails: [String] = []

        var summary: String {
            var lines = ["\(created) neu angelegt, \(updated) aktualisiert, \(skipped) übersprungen."]
            if !skippedDetails.isEmpty {
                lines.append("")
                lines.append(contentsOf: skippedDetails)
            }
            return lines.joined(separator: "\n")
        }
    }

    /// Parses `data` as a JSON array of `TrainingIO`, then for each entry:
    /// matches an existing `Training` by `id` first (this is what makes
    /// re-importing a previously exported file idempotent), falling back to
    /// title (case-insensitive) + startDate within the same minute (exact
    /// `Date` equality is too fragile — a UI-created training can carry
    /// sub-minute noise in its seconds component that a round-tripped
    /// ISO8601 string won't reproduce), and either updates that training in
    /// place or inserts a new one.
    ///
    /// Unlike `MemberImportExport`'s conservative fill-if-blank update, this
    /// mirrors `TeamImportExport`'s "sync to latest" behavior: any
    /// non-empty provided field overwrites the existing value, since a
    /// training re-export represents its current intended state (e.g.
    /// correcting next month's schedule), not sensitive personal data that
    /// should only ever be filled once.
    ///
    /// `teams` (matched by name, case-insensitive, against the real Team
    /// roster — never auto-created) only replaces the training's team
    /// assignment when at least one named team actually resolves; an
    /// omitted or entirely-unresolvable list leaves the existing assignment
    /// untouched rather than silently clearing it. Unresolvable team names
    /// are reported in `skippedDetails` without blocking the rest of the row.
    ///
    /// Entries missing a title or a parseable `startDate` are skipped,
    /// matching `MemberImportExport`'s "skip bad rows, don't abort the
    /// batch" behavior.
    @MainActor
    static func importTrainings(from data: Data, into existingTrainings: [Training], modelContext: ModelContext) -> ImportResult {
        var result = ImportResult()
        let rows: [TrainingIO]
        do {
            rows = try JSONDecoder().decode([TrainingIO].self, from: data)
        } catch {
            result.skipped = 1
            result.skippedDetails = ["Datei konnte nicht gelesen werden: \(error.localizedDescription)"]
            return result
        }

        let allTeams = (try? modelContext.fetch(FetchDescriptor<Team>())) ?? []
        var workingTrainings = existingTrainings

        for row in rows {
            let title = (row.title ?? "").trimmingCharacters(in: .whitespaces)
            guard !title.isEmpty else {
                result.skipped += 1
                result.skippedDetails.append("Übersprungen: Eintrag ohne Titel.")
                continue
            }
            guard let startDate = parseDate(row.startDate) else {
                result.skipped += 1
                result.skippedDetails.append("Übersprungen: \"\(title)\" ohne gültiges Startdatum.")
                continue
            }

            let requestedTeamNames = row.teams ?? []
            let resolvedTeams = requestedTeamNames.compactMap { name in
                allTeams.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
            }

            let training: Training
            if let existing = findExisting(row: row, title: title, startDate: startDate, in: workingTrainings) {
                existing.title = title
                overwriteIfNonEmpty(&existing.sport, row.sport)
                overwriteIfNonEmpty(&existing.location, row.location)
                overwriteIfNonEmpty(&existing.street, row.street)
                overwriteIfNonEmpty(&existing.zip, row.zip)
                overwriteIfNonEmpty(&existing.city, row.city)
                overwriteIfNonEmpty(&existing.country, row.country)
                overwriteIfNonEmpty(&existing.focusArea, row.focusArea)
                overwriteIfNonEmpty(&existing.notes, row.notes)
                existing.startDate = startDate
                if let durationMinutes = row.durationMinutes, durationMinutes > 0 {
                    existing.durationMinutes = durationMinutes
                }
                existing.recomputeEndDate()
                if !resolvedTeams.isEmpty {
                    existing.teams = resolvedTeams
                }
                training = existing
                result.updated += 1
            } else {
                let newTraining = Training(
                    title: title,
                    sport: row.sport ?? "",
                    location: row.location ?? "",
                    street: row.street ?? "",
                    zip: row.zip ?? "",
                    city: row.city ?? "",
                    country: row.country ?? "",
                    startDate: startDate,
                    durationMinutes: (row.durationMinutes.map { $0 > 0 ? $0 : 90 }) ?? 90,
                    focusArea: row.focusArea ?? "",
                    notes: row.notes ?? "",
                    teams: resolvedTeams
                )
                modelContext.insert(newTraining)
                workingTrainings.append(newTraining)
                training = newTraining
                result.created += 1
            }

            for name in requestedTeamNames where !allTeams.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
                result.skippedDetails.append("Team \"\(name)\" bei \"\(title)\" nicht gefunden — nicht zugewiesen.")
            }

            CloudKitSync.shared.pushTraining(training)
        }

        try? modelContext.save()
        return result
    }

    private static func overwriteIfNonEmpty(_ existing: inout String, _ newValue: String?) {
        guard let newValue, !newValue.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        existing = newValue
    }

    private static func findExisting(row: TrainingIO, title: String, startDate: Date, in trainings: [Training]) -> Training? {
        if let idString = row.id, let id = UUID(uuidString: idString),
           let byID = trainings.first(where: { $0.id == id }) {
            return byID
        }
        return trainings.first {
            $0.title.caseInsensitiveCompare(title) == .orderedSame &&
            abs($0.startDate.timeIntervalSince(startDate)) < 60
        }
    }

    /// Accepts full ISO8601 first, then falls back to
    /// `MemberImportExport.parseFlexibleDate`'s "yyyy-MM-dd"/"dd.MM.yyyy"
    /// forms (which have no time component — a training imported that way
    /// lands at midnight and needs its time corrected by hand).
    private static func parseDate(_ raw: String?) -> Date? {
        guard let raw, !raw.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        if let date = isoFormatter.date(from: raw) { return date }
        return MemberImportExport.parseFlexibleDate(raw)
    }
}
