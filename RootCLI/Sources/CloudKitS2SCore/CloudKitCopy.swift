import Foundation

/// Maps the CloudKit public database's club data onto the Supabase tables
/// from migration 20261013000001 (`rootcli cloudkit-copy-to-supabase`).
/// Pure: CloudKit records in, PostgREST rows out — the command does the I/O.
///
/// Ids stay the CloudKit record names (lowercased UUIDs), so every reference
/// between rows — and the app's cached SwiftData objects — keeps resolving.
/// Rows whose required reference is missing (e.g. a membership whose team
/// was deleted) are skipped and reported, never inserted half-broken.
public enum CloudKitCopy {
    /// CloudKit record types in dependency order, as they are read.
    public static let recordTypes = [
        "ClubMember", "Team", "TeamMembership", "SportEvent", "Training", "Tournament",
        "TrainingAttendance", "TournamentAttendance", "EventParticipation", "EventMembership",
        "BudgetEntry", "TrainingFavorite", "WelcomeContent", "MemberChangeRequest",
        "EventImage", "ExpenseReceipt"
    ]

    /// Record types with files (CKAssets). Neither environment had any when
    /// this was written; the copy refuses rather than dropping files.
    public static let assetTypes: Set<String> = ["EventImage", "ExpenseReceipt"]

    /// One target table's rows, in insert order.
    public struct Batch {
        public let table: String
        public var rows: [[String: Any]] = []
        /// PostgREST `on_conflict` target.
        public let conflictKey: String
    }

    public struct Result {
        public var batches: [Batch] = []
        public var skipped: [String] = []
    }

    /// - Parameters:
    ///   - records: every record per CloudKit type (all of them, also for a
    ///     `since` run — references are checked against the full set).
    ///   - existingUserIDs: Supabase auth user ids (lowercased); references to
    ///     other accounts become null (optional links) or skip the row.
    ///   - since: only rows for records modified after this time.
    public static func map(_ records: [String: [CKRecordDTO]], existingUserIDs: Set<String>,
                           since: Date? = nil) throws -> Result {
        for type in assetTypes where !(records[type] ?? []).isEmpty {
            throw CLIError.message("\(records[type]!.count) \(type) record(s) carry files; copying files is not implemented. Copy them by hand first.")
        }
        var result = Result()
        func all(_ type: String) -> [CKRecordDTO] { records[type] ?? [] }
        func changed(_ type: String) -> [CKRecordDTO] {
            all(type).filter { record in
                guard let since else { return true }
                return (record.modifiedAt ?? .distantFuture) > since
            }
        }
        func ids(_ types: String...) -> Set<String> {
            Set(types.flatMap(all).compactMap { id($0.recordName) })
        }
        let memberIDs = ids("ClubMember")
        let teamIDs = ids("Team")
        let membershipIDs = Set(all("TeamMembership").compactMap { record -> String? in
            guard let team = id(record.stringField("teamID")), teamIDs.contains(team) else { return nil }
            return id(record.recordName)
        })
        let eventIDs = ids("SportEvent", "Training", "Tournament")
        func user(_ raw: String?) -> Any { id(raw).flatMap { existingUserIDs.contains($0) ? $0 : nil } ?? NSNull() }
        func optionalRef(_ raw: String?, in set: Set<String>) -> Any { id(raw).flatMap { set.contains($0) ? $0 : nil } ?? NSNull() }
        func skip(_ record: CKRecordDTO, _ why: String) {
            result.skipped.append("\(record.recordType) \(record.recordName): \(why)")
        }

        // Roster: names for everyone approved, contact details separately.
        var members = Batch(table: "members", conflictKey: "id")
        var contacts = Batch(table: "member_contacts", conflictKey: "id")
        for record in changed("ClubMember") {
            guard let rowID = id(record.recordName) else { skip(record, "id is not a UUID"); continue }
            members.rows.append([
                "id": rowID,
                "first_name": text(record, "firstName"), "last_name": text(record, "lastName"),
                "member_number": text(record, "memberNumber"), "sport_id": text(record, "sportId"),
                "default_function": text(record, "defaultFunction"),
                // Absent on old records = member (same default as the app).
                "member_of_gvsc": record.numberField("memberOfGVSC")?.boolValue ?? true,
                "joined_at": iso(record.dateField("joinedAt") ?? Date())
            ])
            contacts.rows.append([
                "id": rowID,
                "street": text(record, "street"), "zip": text(record, "zip"), "city": text(record, "city"),
                "country": text(record, "country"), "email": text(record, "email"), "phone": text(record, "phone"),
                "notes": text(record, "notes"), "gender": text(record, "gender"), "title": text(record, "title")
            ])
        }

        var teams = Batch(table: "teams", conflictKey: "id")
        for record in changed("Team") {
            guard let rowID = id(record.recordName) else { skip(record, "id is not a UUID"); continue }
            teams.rows.append([
                "id": rowID, "name": text(record, "name"), "sport": text(record, "sport"),
                "description_text": text(record, "descriptionText"),
                "created_at": iso(record.dateField("createdAt") ?? Date())
            ])
        }

        var memberships = Batch(table: "team_memberships", conflictKey: "id")
        for record in changed("TeamMembership") {
            guard let rowID = id(record.recordName) else { skip(record, "id is not a UUID"); continue }
            guard let team = id(record.stringField("teamID")), teamIDs.contains(team) else {
                skip(record, "team \(record.stringField("teamID") ?? "-") does not exist"); continue
            }
            memberships.rows.append([
                "id": rowID, "team_id": team,
                "member_id": optionalRef(record.stringField("clubMemberID"), in: memberIDs),
                "user_id": user(record.stringField("userID")),
                "role": record.stringField("role") ?? "player",
                "joined_at": iso(record.dateField("joinedAt") ?? Date())
            ])
        }

        // SportEvent / Training / Tournament -> events (one table, `kind`).
        var events = Batch(table: "events", conflictKey: "id")
        for (type, kind) in [("SportEvent", "event"), ("Training", "training"), ("Tournament", "tournament")] {
            for record in changed(type) {
                guard let rowID = id(record.recordName) else { skip(record, "id is not a UUID"); continue }
                guard let start = record.dateField("startDate") else { skip(record, "no startDate"); continue }
                var row: [String: Any] = [
                    "id": rowID, "kind": kind,
                    // Old Tournament records used name/venue instead of title/location.
                    "title": record.stringField("title") ?? record.stringField("name") ?? "",
                    "sport": text(record, "sport"),
                    "location": record.stringField("location") ?? record.stringField("venue") ?? "",
                    "street": text(record, "street"), "zip": text(record, "zip"), "city": text(record, "city"),
                    "country": text(record, "country"),
                    "start_date": iso(start), "end_date": iso(record.dateField("endDate") ?? start),
                    "notes": text(record, "notes"), "status": text(record, "status"),
                    "created_by": text(record, "createdBy"),
                    "created_at": iso(record.dateField("createdAt") ?? Date()),
                    "duration_minutes": NSNull(), "focus_area": NSNull(), "max_teams": NSNull(),
                    // Only teams that exist; order kept, duplicates dropped.
                    "team_ids": unique(record.stringListField("teamIDs").compactMap(id).filter(teamIDs.contains))
                ]
                if kind == "training" {
                    row["duration_minutes"] = record.numberField("durationMinutes")?.intValue ?? NSNull()
                    row["focus_area"] = text(record, "focusArea")
                }
                if kind == "tournament" {
                    row["max_teams"] = record.numberField("maxTeams")?.intValue ?? NSNull()
                }
                events.rows.append(row)
            }
        }

        var attendances = Batch(table: "attendances", conflictKey: "id")
        for (type, eventField) in [("TrainingAttendance", "trainingID"), ("TournamentAttendance", "tournamentID")] {
            for record in changed(type) {
                guard let rowID = id(record.recordName) else { skip(record, "id is not a UUID"); continue }
                guard let event = id(record.stringField(eventField)), eventIDs.contains(event) else {
                    skip(record, "event does not exist"); continue
                }
                guard let membership = id(record.stringField("membershipID")), membershipIDs.contains(membership) else {
                    skip(record, "membership does not exist"); continue
                }
                attendances.rows.append([
                    "id": rowID, "event_id": event, "membership_id": membership,
                    "attended": record.boolField("attended"),
                    "recorded_at": iso(record.dateField("recordedAt") ?? Date()),
                    "prae_amount": record.numberField("praeAmount")?.doubleValue ?? NSNull()
                ])
            }
        }

        var participations = Batch(table: "event_participations", conflictKey: "id")
        for record in changed("EventParticipation") {
            guard let rowID = id(record.recordName) else { skip(record, "id is not a UUID"); continue }
            guard let event = id(record.stringField("eventID")), eventIDs.contains(event) else {
                skip(record, "event does not exist"); continue
            }
            guard let account = id(record.stringField("userID")), existingUserIDs.contains(account) else {
                skip(record, "account does not exist in Supabase"); continue
            }
            participations.rows.append([
                "id": rowID, "event_id": event, "user_id": account,
                "status": record.stringField("status") ?? "invited",
                "registered_at": iso(record.dateField("registeredAt") ?? Date())
            ])
        }

        var eventMembers = Batch(table: "event_memberships", conflictKey: "id")
        for record in changed("EventMembership") {
            guard let rowID = id(record.recordName) else { skip(record, "id is not a UUID"); continue }
            guard let event = id(record.stringField("eventID")), eventIDs.contains(event) else {
                skip(record, "event does not exist"); continue
            }
            let member = optionalRef(record.stringField("memberID"), in: memberIDs)
            let account = user(record.stringField("userID"))
            guard !(member is NSNull && account is NSNull) else { skip(record, "neither member nor account exists"); continue }
            eventMembers.rows.append([
                "id": rowID, "event_id": event, "member_id": member, "user_id": account,
                "added_at": iso(record.dateField("addedAt") ?? Date())
            ])
        }

        var budget = Batch(table: "budget_entries", conflictKey: "id")
        for record in changed("BudgetEntry") {
            guard let rowID = id(record.recordName) else { skip(record, "id is not a UUID"); continue }
            guard let amount = record.numberField("amount") else { skip(record, "no amount"); continue }
            budget.rows.append([
                "id": rowID, "category": text(record, "category"), "amount": amount.doubleValue,
                "date": iso(record.dateField("date") ?? Date()), "note": text(record, "note"),
                "event_id": optionalRef(record.stringField("eventID"), in: eventIDs),
                "created_by": text(record, "createdBy"),
                "created_at": iso(record.dateField("createdAt") ?? Date())
            ])
        }

        var favorites = Batch(table: "training_favorites", conflictKey: "id")
        for record in changed("TrainingFavorite") {
            guard let rowID = id(record.recordName) else { skip(record, "id is not a UUID"); continue }
            func int(_ name: String, _ fallback: Int) -> Int { record.numberField(name)?.intValue ?? fallback }
            favorites.rows.append([
                "id": rowID, "title": text(record, "title"), "sport": text(record, "sport"),
                "weekday": int("weekday", 2),
                "start_hour": int("startHour", 0), "start_minute": int("startMinute", 0),
                "end_hour": int("endHour", 0), "end_minute": int("endMinute", 0),
                "location": text(record, "location"), "street": text(record, "street"), "zip": text(record, "zip"),
                "city": text(record, "city"), "country": text(record, "country"),
                "team_ids": unique(record.stringListField("teamIDs").compactMap(id).filter(teamIDs.contains)),
                "last_used_at": iso(record.dateField("lastUsedAt") ?? Date())
            ])
        }

        var welcome = Batch(table: "welcome_content", conflictKey: "id")
        for record in changed("WelcomeContent") {
            guard let rowID = id(record.recordName) else { skip(record, "id is not a UUID"); continue }
            welcome.rows.append([
                "id": rowID, "markdown": text(record, "markdown"), "is_enabled": record.boolField("isEnabled")
            ])
        }

        var requests = Batch(table: "member_change_requests", conflictKey: "id")
        for record in changed("MemberChangeRequest") {
            guard let rowID = id(record.recordName) else { skip(record, "id is not a UUID"); continue }
            guard let member = id(record.stringField("memberID")), memberIDs.contains(member) else {
                skip(record, "member does not exist"); continue
            }
            var row: [String: Any] = [
                "id": rowID, "member_id": member, "user_id": NSNull(),
                "requested_by": text(record, "requestedBy"),
                "requested_at": iso(record.dateField("requestedAt") ?? Date()),
                "status": record.stringField("status") ?? "pending",
                "reviewed_by": text(record, "reviewedBy"),
                "reviewed_at": record.dateField("reviewedAt").map(iso) ?? NSNull()
            ]
            for (field, column) in [("firstName", "first_name"), ("lastName", "last_name"), ("title", "title"),
                                    ("gender", "gender"), ("street", "street"), ("zip", "zip"), ("city", "city"),
                                    ("country", "country"), ("email", "email"), ("phone", "phone"),
                                    ("sportId", "sport_id")] {
                row[column] = text(record, field)
            }
            requests.rows.append(row)
        }

        result.batches = [members, contacts, teams, memberships, events, attendances,
                          participations, eventMembers, budget, favorites, welcome, requests]
        return result
    }

    // MARK: - helpers

    /// Lowercased UUID string, or nil if `raw` isn't a UUID.
    static func id(_ raw: String?) -> String? {
        raw.flatMap(UUID.init(uuidString:)).map { $0.uuidString.lowercased() }
    }

    static func unique(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        return ids.filter { seen.insert($0).inserted }
    }

    static func text(_ record: CKRecordDTO, _ field: String) -> String {
        record.stringField(field) ?? ""
    }

    static func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
