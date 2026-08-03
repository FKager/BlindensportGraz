import Foundation
import SwiftData

/// JSON shape for one team-roster row within a `TeamIO.members` array. Person
/// identification uses plain firstName/lastName/email rather than a Member/
/// User id, since a Team export should be usable standalone (no dependency on
/// exchanging Member ids out of band first) — mirrors how `MemberIO` already
/// identifies people by name/email rather than requiring ids to round-trip.
struct TeamMembershipIO: Codable {
    var id: String?
    var firstName: String?
    var lastName: String?
    var email: String?
    var role: String?
    var joinedAt: String?
}

/// JSON shape for one team export, nesting its full membership roster so a
/// single file captures "this team, and everyone on it" in one shot. Field
/// names for the team itself mirror `Team`'s own stored properties.
struct TeamIO: Codable {
    var id: String?
    var name: String?
    var sport: String?
    var descriptionText: String?
    var members: [TeamMembershipIO]?
}

enum TeamImportExport {
    private static let isoFormatter = ISO8601DateFormatter()

    // MARK: - Export

    /// Encodes the given teams (with their memberships) to pretty-printed,
    /// sorted-key JSON and writes it to a fresh temp file, ready for
    /// `ShareLink` — same eager-generation convention as
    /// `MemberImportExport.exportFile`.
    static func exportFile(teams: [Team]) throws -> URL {
        let rows = teams
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .map { team in
                TeamIO(
                    id: team.id.uuidString,
                    name: team.name,
                    sport: team.sport,
                    descriptionText: team.descriptionText,
                    members: team.memberships.sortedByLastName().map { membership in
                        TeamMembershipIO(
                            id: membership.id.uuidString,
                            firstName: membership.firstName,
                            lastName: membership.lastName,
                            email: membership.user?.email ?? membership.member?.email,
                            role: membership.role,
                            joinedAt: isoFormatter.string(from: membership.joinedAt)
                        )
                    }
                )
            }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(rows)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("grazer-vsc-teams-\(dateStamp()).json")
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
        var teamsCreated = 0
        var teamsUpdated = 0
        var membershipsCreated = 0
        var membersCreated = 0
        var skippedDetails: [String] = []

        var summary: String {
            var lines = [
                "\(teamsCreated) Team(s) neu, \(teamsUpdated) aktualisiert.",
                "\(membershipsCreated) Mitgliedschaft(en) angelegt, \(membersCreated) neue Mitglieder im Register angelegt."
            ]
            if !skippedDetails.isEmpty {
                lines.append("")
                lines.append(contentsOf: skippedDetails)
            }
            return lines.joined(separator: "\n")
        }
    }

    /// Parses `data` as a JSON array of `TeamIO`. For each team: matches an
    /// existing `Team` by `id` first, falling back to a case-insensitive name
    /// match, and either updates that team in place or inserts a new one
    /// (sport/description only fill in when non-empty, existing team fields
    /// are never blanked). For each nested membership row: skips a row
    /// already present on that team (matched by name, so re-importing a
    /// previously exported file is idempotent), otherwise resolves the person
    /// against existing `User` accounts first (email, then name — app
    /// accounts can't be created by import), then the `Member` roster (email,
    /// then name), creating a brand-new `Member` entry only as a last resort
    /// — matching `MemberImportExport.importMembers`'s own
    /// create-if-not-found behavior, so a team file with names nobody has
    /// entered into the roster yet still works.
    @MainActor
    static func importTeams(from data: Data, modelContext: ModelContext) -> ImportResult {
        var result = ImportResult()
        let rows: [TeamIO]
        do {
            rows = try JSONDecoder().decode([TeamIO].self, from: data)
        } catch {
            result.skippedDetails = ["Datei konnte nicht gelesen werden: \(error.localizedDescription)"]
            return result
        }

        var teams = (try? modelContext.fetch(FetchDescriptor<Team>())) ?? []
        var users = (try? modelContext.fetch(FetchDescriptor<User>())) ?? []
        var members = (try? modelContext.fetch(FetchDescriptor<Member>())) ?? []

        for row in rows {
            let name = (row.name ?? "").trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else {
                result.skippedDetails.append("Team übersprungen: kein Name angegeben.")
                continue
            }

            let team: Team
            if let existing = findExistingTeam(row: row, name: name, in: teams) {
                team = existing
                team.name = name
                if let sport = row.sport, !sport.trimmingCharacters(in: .whitespaces).isEmpty {
                    team.sport = sport
                }
                if let descriptionText = row.descriptionText, !descriptionText.trimmingCharacters(in: .whitespaces).isEmpty {
                    team.descriptionText = descriptionText
                }
                result.teamsUpdated += 1
            } else {
                team = Team(id: row.id.flatMap(UUID.init) ?? UUID(),
                             name: name,
                             sport: row.sport ?? "",
                             descriptionText: row.descriptionText ?? "")
                modelContext.insert(team)
                teams.append(team)
                result.teamsCreated += 1
            }

            for membershipRow in row.members ?? [] {
                importMembership(membershipRow, into: team, users: &users, members: &members,
                                  modelContext: modelContext, result: &result)
            }

            CloudKitSync.shared.pushTeam(team)
        }

        try? modelContext.save()
        // A team import can fall back to creating brand-new Member roster
        // entries (see importMembership below) — one snapshot for the whole
        // batch if that happened, same convention as
        // MemberImportExport.importMembers.
        if result.membersCreated > 0 {
            MemberBackup.snapshot(members: members)
        }
        return result
    }

    private static func findExistingTeam(row: TeamIO, name: String, in teams: [Team]) -> Team? {
        if let idString = row.id, let id = UUID(uuidString: idString),
           let byID = teams.first(where: { $0.id == id }) {
            return byID
        }
        return teams.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    @MainActor
    private static func importMembership(_ row: TeamMembershipIO, into team: Team,
                                          users: inout [User], members: inout [Member],
                                          modelContext: ModelContext, result: inout ImportResult) {
        let firstName = (row.firstName ?? "").trimmingCharacters(in: .whitespaces)
        let lastName = (row.lastName ?? "").trimmingCharacters(in: .whitespaces)
        guard !firstName.isEmpty, !lastName.isEmpty else {
            result.skippedDetails.append("Mitgliedschaft in \"\(team.name)\" übersprungen: kein Vor-/Nachname.")
            return
        }

        // Already on this team's roster? Update the role in place rather than
        // creating a duplicate TeamMembership for the same person.
        if let existingMembership = team.memberships.first(where: {
            $0.firstName.caseInsensitiveCompare(firstName) == .orderedSame &&
            $0.lastName.caseInsensitiveCompare(lastName) == .orderedSame
        }) {
            if let role = row.role, !role.isEmpty { existingMembership.role = role }
            CloudKitSync.shared.pushMembership(existingMembership)
            return
        }

        let role = row.role ?? "player"
        let joinedAt = MemberImportExport.parseFlexibleDate(row.joinedAt) ?? Date()
        let normalizedEmail = (row.email ?? "").trimmingCharacters(in: .whitespaces).lowercased()

        if let user = findPerson(email: normalizedEmail, firstName: firstName, lastName: lastName, in: users) {
            let membership = TeamMembership(user: user, team: team, role: role, joinedAt: joinedAt)
            modelContext.insert(membership)
            CloudKitSync.shared.pushMembership(membership)
            result.membershipsCreated += 1
            return
        }

        let member: Member
        if let existing = findPerson(email: normalizedEmail, firstName: firstName, lastName: lastName, in: members) {
            member = existing
        } else {
            let newMember = Member(firstName: firstName, lastName: lastName, email: row.email ?? "")
            modelContext.insert(newMember)
            members.append(newMember)
            CloudKitSync.shared.pushMember(newMember)
            result.membersCreated += 1
            member = newMember
        }

        let membership = TeamMembership(member: member, team: team, role: role, joinedAt: joinedAt)
        modelContext.insert(membership)
        CloudKitSync.shared.pushMembership(membership)
        result.membershipsCreated += 1
    }

    /// Matches by email first (if a normalized, non-empty email was given),
    /// falling back to case-insensitive first+last name — same priority
    /// `MemberImportExport.findExisting`/`Member.matches` already use.
    private static func findPerson(email: String, firstName: String, lastName: String, in people: [User]) -> User? {
        if !email.isEmpty, let byEmail = people.first(where: { $0.email.trimmingCharacters(in: .whitespaces).lowercased() == email }) {
            return byEmail
        }
        return people.first {
            $0.firstName.caseInsensitiveCompare(firstName) == .orderedSame &&
            $0.lastName.caseInsensitiveCompare(lastName) == .orderedSame
        }
    }

    private static func findPerson(email: String, firstName: String, lastName: String, in people: [Member]) -> Member? {
        if !email.isEmpty, let byEmail = people.first(where: { $0.email.trimmingCharacters(in: .whitespaces).lowercased() == email }) {
            return byEmail
        }
        return people.first {
            $0.firstName.caseInsensitiveCompare(firstName) == .orderedSame &&
            $0.lastName.caseInsensitiveCompare(lastName) == .orderedSame
        }
    }
}
