import Foundation
import CloudKitS2SCore

/// One-off move of accounts, roles, approvals and sensitive member data from
/// the CloudKit public database to Supabase, plus the follow-up reset emails
/// and the CloudKit scrub. Every command is a dry run unless `--apply`.
///
/// Needs both the CloudKit S2S variables (CLOUDKIT_*) and SUPABASE_URL /
/// SUPABASE_SERVICE_KEY. Safe to re-run: existing accounts, roles, approvals
/// and protected rows are left untouched.
enum SupabaseMigrate {
    static let redirectURL = "blindensportgraz://auth-callback"
    static let designatedRootEmail = "blindensport.gvsc@gmail.com"

    // MARK: - supabase-migrate

    static func runMigrate(_ args: [String], cloudKit: CloudKitS2SClient) async throws {
        let apply = try applyFlag(args, usage: "rootcli supabase-migrate --dry-run|--apply")
        let supabase = try SupabaseAdminClient.fromEnvironment()

        let identities = try await cloudKit.queryRecords(recordType: "UserIdentity")
        let assignments = try await cloudKit.queryRecords(recordType: "RoleAssignment")
        let approvals = try await cloudKit.queryRecords(recordType: "AccountApproval")
        let members = try await cloudKit.queryRecords(recordType: "ClubMember")
        print("CloudKit: \(identities.count) accounts, \(assignments.count) role assignments, "
              + "\(approvals.count) approvals, \(members.count) roster entries")

        let existing = try await supabase.listUsers()
        let existingIDs = Set(existing.map(\.id))
        let existingEmails = Set(existing.compactMap { $0.email?.lowercased() })
        let roles = effectiveRoles(identities: identities, assignments: assignments)

        var migrated: [UUID] = []
        var seenEmails = Set<String>()
        var skipped: [String] = []
        for identity in identities.sorted(by: { $0.recordName < $1.recordName }) {
            guard let id = UUID(uuidString: identity.recordName) else {
                skipped.append("\(identity.recordName): not a UUID"); continue
            }
            let email = (identity.stringField("email") ?? "").trimmingCharacters(in: .whitespaces).lowercased()
            let name = "\(identity.stringField("firstName") ?? "") \(identity.stringField("lastName") ?? "")"
            guard !email.isEmpty else { skipped.append("\(name) (\(id)): no email"); continue }
            guard seenEmails.insert(email).inserted else {
                skipped.append("\(name) (\(id)): duplicate email \(email)"); continue
            }
            if existingIDs.contains(id) { migrated.append(id); continue }
            if existingEmails.contains(email) {
                skipped.append("\(name) (\(id)): \(email) already registered with another id"); continue
            }
            print("  + \(name) <\(email)> role=\(roles[id]?.rawValue ?? "pending")")
            if apply {
                guard let created = try await supabase.createUser(
                    id: id, email: email,
                    firstName: identity.stringField("firstName") ?? "",
                    lastName: identity.stringField("lastName") ?? "") else {
                    skipped.append("\(name): email already registered"); continue
                }
                guard created.id == id else {
                    throw CLIError.message("Supabase assigned \(created.id) instead of \(id) for \(email); "
                                           + "stop and add an id mapping before continuing.")
                }
                // Keep existing webcal links working.
                var profile: [String: Any] = ["is_gvsc_member": identity.boolField("isGrazerVSCMember")]
                if let token = identity.stringField("calendarToken"), !token.isEmpty {
                    profile["calendar_token"] = token
                }
                try await supabase.update(table: "profiles", filters: [("id", "eq.\(id.uuidString.lowercased())")],
                                          values: profile)
            }
            migrated.append(id)
        }

        let migratedSet = Set(migrated)
        let roleRows: [[String: Any]] = roles
            .filter { migratedSet.contains($0.key) }
            .map { ["user_id": $0.key.uuidString.lowercased(), "role": $0.value.rawValue] }
        let approvalRows: [[String: Any]] = approvals.compactMap { record in
            guard let userID = record.stringField("userID").flatMap(UUID.init(uuidString:)),
                  migratedSet.contains(userID),
                  let memberID = record.stringField("memberID").flatMap(UUID.init(uuidString:)) else { return nil }
            var row: [String: Any] = ["user_id": userID.uuidString.lowercased(),
                                      "member_id": memberID.uuidString.lowercased()]
            if let approver = record.stringField("approvedBy").flatMap(UUID.init(uuidString:)),
               migratedSet.contains(approver) {
                row["approved_by"] = approver.uuidString.lowercased()
            }
            if let at = record.dateField("approvedAt") { row["approved_at"] = iso(at) }
            return row
        }
        let privateRows: [[String: Any]] = members.compactMap(privateRow)

        print("Roles: \(roleRows.count), approvals: \(approvalRows.count), protected member rows: \(privateRows.count)")
        if !skipped.isEmpty {
            print("Skipped \(skipped.count):")
            skipped.forEach { print("  - \($0)") }
        }
        guard apply else {
            print("Dry run — nothing written. Re-run with --apply.")
            return
        }
        // Insert-if-missing only: a re-run (e.g. for accounts registered on
        // old app builds) never overwrites roles, approvals or protected
        // data already changed in Supabase.
        try await supabase.upsert(table: "user_roles", rows: roleRows, onConflict: "user_id",
                                  ignoreDuplicates: true)
        try await supabase.upsert(table: "account_approvals", rows: dedupe(approvalRows, key: "user_id"),
                                  onConflict: "user_id", ignoreDuplicates: true)
        try await supabase.upsert(table: "member_private", rows: privateRows, onConflict: "member_id",
                                  ignoreDuplicates: true)
        print("Done: \(migrated.count) accounts in Supabase.")
    }

    /// Same rule as the app's former RoleAssignmentResolver: the latest
    /// assignment by a root account or RootCLI wins, else the account's own
    /// stored role; `isRoot` and the club's designated account become `root`.
    static func effectiveRoles(identities: [CKRecordDTO], assignments: [CKRecordDTO]) -> [UUID: Role] {
        let rootIDs = Set(identities.filter { $0.boolField("isRoot") }.map(\.recordName))
        var latest: [String: (Date, String)] = [:]
        for record in assignments {
            guard let user = record.stringField("userID"), let role = record.stringField("role") else { continue }
            let by = record.stringField("assignedBy") ?? ""
            guard by == "system:rootcli" || rootIDs.contains(by) else { continue }
            let at = record.dateField("assignedAt") ?? .distantPast
            if latest[user].map({ at > $0.0 }) ?? true { latest[user] = (at, role) }
        }
        var result: [UUID: Role] = [:]
        for identity in identities {
            guard let id = UUID(uuidString: identity.recordName) else { continue }
            let email = (identity.stringField("email") ?? "").lowercased()
            if identity.boolField("isRoot") || email == designatedRootEmail {
                result[id] = .root
                continue
            }
            let raw = latest[identity.recordName]?.1 ?? identity.stringField("role") ?? "member"
            result[id] = Role(rawValue: raw) ?? .member
        }
        return result
    }

    enum Role: String { case member, coach, admin, root }

    private static func privateRow(_ member: CKRecordDTO) -> [String: Any]? {
        guard let id = UUID(uuidString: member.recordName) else { return nil }
        let svnr = member.stringField("svnr") ?? ""
        let iban = member.stringField("iban") ?? ""
        let birth = member.dateField("birthDate")
        let exam = member.dateField("lastMedicalExamination")
        guard !svnr.isEmpty || !iban.isEmpty || birth != nil || exam != nil else { return nil }
        // Every row needs the same keys for a PostgREST bulk insert.
        return ["member_id": id.uuidString.lowercased(), "svnr": svnr, "iban": iban,
                "birth_date": birth.map(day) ?? NSNull(),
                "last_medical_examination": exam.map(day) ?? NSNull()]
    }

    // MARK: - supabase-send-resets

    static func runSendResets(_ args: [String]) async throws {
        let apply = try applyFlag(args, usage: "rootcli supabase-send-resets --dry-run|--apply")
        let supabase = try SupabaseAdminClient.fromEnvironment()
        let users = try await supabase.listUsers().filter { !($0.email ?? "").isEmpty }
        print("\(users.count) accounts with email.")
        for user in users {
            print("  → \(user.email!)")
            if apply {
                try await supabase.sendPasswordReset(email: user.email!, redirectTo: redirectURL)
                // Stay well below the auth email rate limit.
                try await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
        if !apply { print("Dry run — no emails sent. Re-run with --apply.") }
    }

    // MARK: - supabase-scrub-cloudkit

    static let memberPrivateFields = ["svnr", "iban", "birthDate", "lastMedicalExamination"]

    /// Removes sensitive fields from CloudKit (rewrites each record without
    /// them) and deletes the UserIdentity / RoleAssignment / AccountApproval
    /// records. Run after the new app build is installed everywhere.
    static func runScrub(_ args: [String], cloudKit: CloudKitS2SClient) async throws {
        let apply = try applyFlag(args, usage: "rootcli supabase-scrub-cloudkit --dry-run|--apply")
        for type in ["ClubMember", "MemberChangeRequest"] {
            let records = try await existingRecords(type, cloudKit: cloudKit)
            let dirty = records.filter { record in memberPrivateFields.contains { record.fields[$0] != nil } }
            print("\(type): \(dirty.count) of \(records.count) records carry protected fields")
            guard apply else { continue }
            for record in dirty {
                let kept = record.fields.filter { !memberPrivateFields.contains($0.key) }
                try await cloudKit.createOrReplaceRecord(recordType: type, recordName: record.recordName, fields: kept)
            }
        }
        for type in ["UserIdentity", "RoleAssignment", "AccountApproval"] {
            let records = try await existingRecords(type, cloudKit: cloudKit)
            print("\(type): \(records.count) records to delete")
            guard apply else { continue }
            for record in records {
                try await cloudKit.deleteRecord(recordType: type, recordName: record.recordName)
            }
        }
        if !apply { print("Dry run — nothing changed. Re-run with --apply.") }
    }

    /// A record type that was never saved in this environment's schema
    /// (e.g. MemberChangeRequest) has nothing to scrub.
    private static func existingRecords(_ type: String, cloudKit: CloudKitS2SClient) async throws -> [CKRecordDTO] {
        do {
            return try await cloudKit.queryRecords(recordType: type)
        } catch let error as CLIError where "\(error)".contains("could not find record_type") {
            print("\(type): record type not in this environment, skipped")
            return []
        }
    }

    // MARK: - set-role

    static func runSetRole(_ args: [String]) async throws {
        guard args.count == 2, let role = Role(rawValue: args[1]) else {
            throw CLIError.message("Usage: rootcli set-role <email|user id> <member|coach|admin|root>")
        }
        let supabase = try SupabaseAdminClient.fromEnvironment()
        let needle = args[0].lowercased()
        let users = try await supabase.listUsers()
        guard let user = users.first(where: { $0.id.uuidString.lowercased() == needle || $0.email?.lowercased() == needle }) else {
            throw CLIError.message("No Supabase account with email or id '\(args[0])'.")
        }
        // Service key: the role_change_log trigger records changed_by = null (System).
        try await supabase.upsert(table: "user_roles",
                                  rows: [["user_id": user.id.uuidString.lowercased(), "role": role.rawValue,
                                          "assigned_at": iso(Date())]],
                                  onConflict: "user_id")
        print("Updated \(user.email ?? user.id.uuidString): role -> \(role.rawValue)")
    }

    // MARK: - helpers

    private static func applyFlag(_ args: [String], usage: String) throws -> Bool {
        switch args.first {
        case "--apply": return true
        case "--dry-run", nil: return false
        default: throw CLIError.message("Usage: \(usage)")
        }
    }

    private static func dedupe(_ rows: [[String: Any]], key: String) -> [[String: Any]] {
        var seen = Set<String>()
        return rows.reversed().filter { seen.insert($0[key] as? String ?? "").inserted }
    }

    private static func iso(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    /// Calendar day as the app showed it (Austria).
    private static func day(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Vienna")!
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }
}
