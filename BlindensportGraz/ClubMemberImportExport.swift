import Foundation
import SwiftData

/// JSON shape for one club member, shared by export and import. Field names
/// intentionally match RootCLI's `ClubMemberInput`/`members.example.json` and
/// `clubmembersapi`'s REST payloads exactly, so a file exported here can be
/// fed to `rootcli import-members` (or vice versa) with no conversion.
/// `joinedAt` is a plain string (not a native JSON date) accepting either
/// "yyyy-MM-dd" or full ISO8601, matching RootCLI's `ClubMemberImport.parseJoinedAt`.
struct ClubMemberIO: Codable {
    var id: String?
    var firstName: String?
    var lastName: String?
    var street: String?
    var zip: String?
    var city: String?
    var email: String?
    var phone: String?
    var memberNumber: String?
    var joinedAt: String?
    var notes: String?
}

enum ClubMemberImportExport {
    private static let isoFormatter = ISO8601DateFormatter()

    // MARK: - Export

    /// Encodes the given roster to pretty-printed, sorted-key JSON and writes
    /// it to a fresh temp file, ready for `ShareLink`.
    static func exportFile(members: [ClubMember]) throws -> URL {
        let rows = members
            .sorted { ($0.lastName, $0.firstName) < ($1.lastName, $1.firstName) }
            .map { member in
                ClubMemberIO(
                    id: member.id.uuidString,
                    firstName: member.firstName,
                    lastName: member.lastName,
                    street: member.street,
                    zip: member.zip,
                    city: member.city,
                    email: member.email,
                    phone: member.phone,
                    memberNumber: member.memberNumber,
                    joinedAt: isoFormatter.string(from: member.joinedAt),
                    notes: member.notes
                )
            }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(rows)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("grazer-vsc-mitglieder-\(dateStamp()).json")
        try data.write(to: url, options: .atomic)
        return url
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

    /// Parses `data` as a JSON array of `ClubMemberIO`, then for each entry:
    /// matches an existing roster entry by `id` first (if given and valid —
    /// this is what makes re-importing a previously exported file idempotent),
    /// falling back to email or first+last name (same rule as
    /// `ClubMember.checkMembership`'s account matching), and either updates
    /// that entry in place or inserts a new `ClubMember`. Entries missing
    /// firstName/lastName are skipped, matching RootCLI's import-members
    /// behavior, so one bad row doesn't abort the whole file.
    @MainActor
    static func importMembers(from data: Data, into roster: [ClubMember], modelContext: ModelContext) -> ImportResult {
        var result = ImportResult()
        let rows: [ClubMemberIO]
        do {
            rows = try JSONDecoder().decode([ClubMemberIO].self, from: data)
        } catch {
            result.skipped = 1
            result.skippedDetails = ["Datei konnte nicht gelesen werden: \(error.localizedDescription)"]
            return result
        }

        var touched: [ClubMember] = []
        var workingRoster = roster

        for row in rows {
            let firstName = (row.firstName ?? "").trimmingCharacters(in: .whitespaces)
            let lastName = (row.lastName ?? "").trimmingCharacters(in: .whitespaces)
            guard !firstName.isEmpty, !lastName.isEmpty else {
                result.skipped += 1
                result.skippedDetails.append("Übersprungen: Eintrag ohne Vor-/Nachnamen.")
                continue
            }

            let joinedAt = parseJoinedAt(row.joinedAt) ?? Date()
            let existing = findExisting(row: row, firstName: firstName, lastName: lastName, in: workingRoster)

            if let existing {
                existing.firstName = firstName
                existing.lastName = lastName
                existing.street = row.street ?? existing.street
                existing.zip = row.zip ?? existing.zip
                existing.city = row.city ?? existing.city
                existing.email = row.email ?? existing.email
                existing.phone = row.phone ?? existing.phone
                existing.memberNumber = row.memberNumber ?? existing.memberNumber
                existing.notes = row.notes ?? existing.notes
                if row.joinedAt != nil { existing.joinedAt = joinedAt }
                touched.append(existing)
                result.updated += 1
            } else {
                let id = row.id.flatMap(UUID.init) ?? UUID()
                let member = ClubMember(
                    id: id,
                    firstName: firstName,
                    lastName: lastName,
                    street: row.street ?? "",
                    zip: row.zip ?? "",
                    city: row.city ?? "",
                    email: row.email ?? "",
                    phone: row.phone ?? "",
                    memberNumber: row.memberNumber ?? "",
                    joinedAt: joinedAt,
                    notes: row.notes ?? ""
                )
                modelContext.insert(member)
                workingRoster.append(member)
                touched.append(member)
                result.created += 1
            }
        }

        try? modelContext.save()
        for member in touched {
            CloudKitSync.shared.pushClubMember(member)
        }
        return result
    }

    private static func findExisting(row: ClubMemberIO, firstName: String, lastName: String, in roster: [ClubMember]) -> ClubMember? {
        if let idString = row.id, let id = UUID(uuidString: idString),
           let byID = roster.first(where: { $0.id == id }) {
            return byID
        }
        let normalizedEmail = (row.email ?? "").trimmingCharacters(in: .whitespaces).lowercased()
        if !normalizedEmail.isEmpty,
           let byEmail = roster.first(where: { $0.email.trimmingCharacters(in: .whitespaces).lowercased() == normalizedEmail }) {
            return byEmail
        }
        let normalizedFirst = firstName.lowercased()
        let normalizedLast = lastName.lowercased()
        return roster.first {
            $0.firstName.trimmingCharacters(in: .whitespaces).lowercased() == normalizedFirst &&
            $0.lastName.trimmingCharacters(in: .whitespaces).lowercased() == normalizedLast
        }
    }

    /// Accepts "yyyy-MM-dd" or full ISO8601; mirrors RootCLI's
    /// `ClubMemberImport.parseJoinedAt` exactly so both tools parse the same
    /// files identically.
    private static func parseJoinedAt(_ raw: String?) -> Date? {
        guard let raw, !raw.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        if let date = isoFormatter.date(from: raw) { return date }
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "yyyy-MM-dd"
        dayFormatter.timeZone = TimeZone(identifier: "UTC")
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        return dayFormatter.date(from: raw)
    }
}
