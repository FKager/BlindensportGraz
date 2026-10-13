import Foundation
import CloudKitS2SCore

@main
struct RootCLI {
    static func main() async {
        do {
            try await run(Array(CommandLine.arguments.dropFirst()))
        } catch {
            FileHandle.standardError.write("Error: \(error)\n".data(using: .utf8)!)
            exit(1)
        }
    }

    static func run(_ args: [String]) async throws {
        guard let command = args.first else {
            printUsage()
            return
        }
        let rest = Array(args.dropFirst())

        switch command {
        case "list":
            try await runList()
        case "set-role":
            try await SupabaseMigrate.runSetRole(rest)
        case "supabase-migrate":
            try await SupabaseMigrate.runMigrate(rest, cloudKit: try makeClient())
        case "supabase-send-resets":
            try await SupabaseMigrate.runSendResets(rest)
        case "supabase-scrub-cloudkit":
            try await SupabaseMigrate.runScrub(rest, cloudKit: try makeClient())
        case "import-members":
            try await runImportMembers(rest)
        case "update-members":
            try await runUpdateMembers(rest)
        case "record":
            try await runRecord(rest)
        case "copy-records":
            try await runCopyRecords(rest)
        case "-h", "--help", "help":
            printUsage()
        default:
            throw CLIError.message("Unknown command '\(command)'. Run `rootcli help` for usage.")
        }
    }

    private static func makeClient() throws -> CloudKitS2SClient {
        try CloudKitS2SClient(config: try Config.fromEnvironment())
    }

    private static func runList() async throws {
        let supabase = try SupabaseAdminClient.fromEnvironment()
        let profiles = try await supabase.select(table: "profiles", columns: "id,email,first_name,last_name")
        let roles = try await supabase.select(table: "user_roles", columns: "user_id,role")
        let approved = Set(try await supabase.select(table: "account_approvals", columns: "user_id")
            .compactMap { $0["user_id"] as? String })
        let roleByUser = Dictionary(roles.compactMap { row -> (String, String)? in
            guard let id = row["user_id"] as? String, let role = row["role"] as? String else { return nil }
            return (id, role)
        }, uniquingKeysWith: { a, _ in a })

        func pad(_ text: String, _ width: Int) -> String {
            text.count >= width ? String(text.prefix(width - 1)) + " " : text.padding(toLength: width, withPad: " ", startingAt: 0)
        }
        print(pad("Name", 28) + pad("Role", 9) + pad("Approved", 10) + "Email")
        for profile in profiles.sorted(by: { ($0["last_name"] as? String ?? "") < ($1["last_name"] as? String ?? "") }) {
            let id = profile["id"] as? String ?? ""
            let name = "\(profile["first_name"] as? String ?? "") \(profile["last_name"] as? String ?? "")"
            print(pad(name, 28) + pad(roleByUser[id] ?? "pending", 9) + pad(approved.contains(id) ? "yes" : "", 10)
                  + (profile["email"] as? String ?? ""))
        }
    }

    private static func runImportMembers(_ args: [String]) async throws {
        guard args.count == 1 else {
            throw CLIError.message("Usage: rootcli import-members <file.json>")
        }
        let inputs = try MemberImport.loadRecords(from: args[0])
        guard !inputs.isEmpty else {
            print("No members found in \(args[0]).")
            return
        }

        let client = try makeClient()
        let result = await MemberBulkImport.run(inputs, client: client, privateStore: try privateStore(for: inputs))
        for message in result.messages { print(message) }
        print("Done: \(result.succeeded) imported, \(result.failed) failed, out of \(inputs.count).")
    }

    /// Unlike `import-members` (blind create-or-replace of the whole record),
    /// this only fills fields that are currently blank on an existing
    /// Member (matched by firstName+lastName) — existing data is never
    /// overwritten. Rows with no existing match are still created fresh.
    private static func runUpdateMembers(_ args: [String]) async throws {
        guard args.count == 1 else {
            throw CLIError.message("Usage: rootcli update-members <file.json>")
        }
        let inputs = try MemberImport.loadRecords(from: args[0])
        guard !inputs.isEmpty else {
            print("No members found in \(args[0]).")
            return
        }

        let client = try makeClient()
        let result = await MemberFillUpdate.run(inputs, client: client, privateStore: try privateStore(for: inputs))
        for message in result.messages { print(message) }
        print("Done: \(result.succeeded) updated/created, \(result.failed) failed, out of \(inputs.count).")
    }

    /// Protected fields (svnr, iban, dates) are stored in Supabase only, so a
    /// file carrying them needs SUPABASE_URL/SUPABASE_SERVICE_KEY. Files
    /// without them run on CloudKit credentials alone.
    private static func privateStore(for inputs: [MemberBulkInput]) throws -> MemberPrivateStore? {
        let env = ProcessInfo.processInfo.environment
        let configured = !(env["SUPABASE_URL"] ?? "").isEmpty && !(env["SUPABASE_SERVICE_KEY"] ?? "").isEmpty
        if configured { return MemberPrivateStore(supabase: try SupabaseAdminClient.fromEnvironment()) }
        guard inputs.allSatisfy({ $0.privateData.isEmpty }) else {
            throw CLIError.message("""
                The file contains protected fields (svnr, iban, birthDate, lastMedicalExamination), \
                which are stored in Supabase. Set SUPABASE_URL and SUPABASE_SERVICE_KEY and run again.
                """)
        }
        return nil
    }

    /// Generic insert/update/read/delete for ANY CloudKit record type this
    /// app publishes — not just Member. Unlike `set-role`/`set-root`
    /// (which hand-decode specific fields of one specific type) or
    /// `import-members` (which mirrors `MemberRecord`), this works
    /// against raw record types and field names via `CKFieldCoding`, so
    /// adding support for a new model never requires touching this file.
    /// `set` always upserts (`createOrReplaceRecord`), matching the app's own
    /// "insert or update, no conflict handling" push semantics.
    private static func runRecord(_ args: [String]) async throws {
        guard let sub = args.first else {
            throw CLIError.message("Usage: rootcli record <list|get|set|delete> ... Run `rootcli help` for details.")
        }
        let rest = Array(args.dropFirst())
        let client = try makeClient()

        switch sub {
        case "list":
            guard rest.count == 1 else {
                throw CLIError.message("Usage: rootcli record list <type>")
            }
            let records = try await client.queryRecords(recordType: rest[0])
            guard !records.isEmpty else {
                print("No \(rest[0]) records found.")
                return
            }
            for record in records {
                print(try recordJSON(id: record.recordName, fields: record.fields))
            }

        case "get":
            guard rest.count == 2 else {
                throw CLIError.message("Usage: rootcli record get <type> <id>")
            }
            guard let dto = try await client.lookupRecord(recordType: rest[0], recordName: rest[1]) else {
                throw CLIError.message("No \(rest[0]) record found with id \(rest[1]).")
            }
            print(try recordJSON(id: dto.recordName, fields: dto.fields))

        case "set":
            guard rest.count >= 3 else {
                throw CLIError.message("Usage: rootcli record set <type> <id> field=value [field:TYPE=value ...]\nTYPE is one of INT64, DOUBLE, TIMESTAMP, STRING_LIST, STRING, ASSET (default STRING when omitted). ASSET's value is a local file path, uploaded via CloudKit's asset-upload flow.")
            }
            let recordType = rest[0]
            let id = rest[1]
            let assignments = Array(rest.dropFirst(2))
            try CloudKitWriteGuard.check(recordType: recordType, fieldNames: assignments.map {
                String($0.prefix { $0 != "=" && $0 != ":" })
            })

            // ASSET assignments need an async upload (assets/upload + a
            // pre-authorized POST, see CloudKitS2SClient.uploadAsset) and
            // can't go through CKFieldCoding's pure, synchronous encoder —
            // pull those out first, upload each, then merge with the
            // ordinary synchronously-encoded fields below.
            var assetAssignments: [(name: String, path: String)] = []
            var otherAssignments: [String] = []
            for arg in assignments {
                guard let eq = arg.firstIndex(of: "="), let colon = arg.firstIndex(of: ":"), colon < eq,
                      arg[arg.index(after: colon)..<eq].uppercased() == "ASSET" else {
                    otherAssignments.append(arg)
                    continue
                }
                let name = String(arg[arg.startIndex..<colon])
                let path = String(arg[arg.index(after: eq)...])
                assetAssignments.append((name, path))
            }

            var fields = CKFieldCoding.parseCLIAssignments(otherAssignments)
            for asset in assetAssignments {
                let singleFile = try await client.uploadAsset(
                    recordType: recordType, fieldName: asset.name, fileURL: URL(fileURLWithPath: asset.path))
                fields[asset.name] = ["value": singleFile, "type": "ASSETID"]
            }
            guard !fields.isEmpty else {
                throw CLIError.message("No valid field=value assignments given.")
            }
            try await client.createOrReplaceRecord(recordType: recordType, recordName: id, fields: fields)
            print("Upserted \(recordType) \(id): \(assignments.joined(separator: ", "))")

        case "delete":
            guard rest.count == 2 else {
                throw CLIError.message("Usage: rootcli record delete <type> <id>")
            }
            // A member's protected data goes with it (Supabase member_private),
            // so a ClubMember delete needs Supabase configured before anything
            // is removed from CloudKit.
            let privateStore = rest[0] == "ClubMember"
                ? MemberPrivateStore(supabase: try SupabaseAdminClient.fromEnvironment()) : nil
            try await client.deleteRecord(recordType: rest[0], recordName: rest[1])
            try await privateStore?.delete(memberID: rest[1])
            print("Deleted \(rest[0]) \(rest[1]).")

        default:
            throw CLIError.message("Unknown record subcommand '\(sub)'. Use list, get, set, or delete.")
        }
    }

    /// Every app-published record type in the public database — the default
    /// set `copy-records` walks. `ExpenseReceipt` and `EventImage` are
    /// intentionally in the list despite carrying a CloudKit asset payload:
    /// their non-asset fields copy fine and the asset field itself is
    /// skipped per-record with a count (an asset can't be re-pointed across
    /// environments — its bytes live in the source env's asset store).
    /// `SportEvent`/`EventParticipation`/`MemberChangeRequest` added
    /// 2026-09-10 — they existed as app-published record types before that
    /// but were never added here, so a `copy-records` run would have
    /// silently skipped any real data of those three types.
    private static let copyableRecordTypes = [
        "UserIdentity", "ClubMember", "Team", "TeamMembership",
        "SportEvent", "Training", "Tournament", "TrainingAttendance", "TournamentAttendance",
        "EventParticipation", "EventMembership", "EventImage", "TrainingFavorite", "RoleChangeLog",
        "ExpenseReceipt", "MemberChangeRequest", "BudgetEntry", "WelcomeContent",
    ]

    /// Bulk-copies every record of the given types from the source CloudKit
    /// environment (`CLOUDKIT_*`) into a destination environment
    /// (`CLOUDKIT_TARGET_*`), preserving each record's name/id so the app's
    /// id-string cross-references (teamID, membershipID, …) stay intact —
    /// something `cktool create-record` can't do (it mints a fresh name).
    /// Upsert semantics (`createOrReplaceRecord`), matching the app's own push.
    /// Typical use: promote Development data to Production after a schema deploy.
    private static func runCopyRecords(_ args: [String]) async throws {
        var dryRun = false
        var types: [String] = []
        for arg in args {
            switch arg {
            case "--dry-run": dryRun = true
            case let flag where flag.hasPrefix("-"):
                throw CLIError.message("Unknown flag '\(flag)'. Usage: rootcli copy-records [--dry-run] [type ...]")
            default: types.append(arg)
            }
        }
        if types.isEmpty { types = copyableRecordTypes }

        let sourceConfig = try Config.fromEnvironment()
        let targetConfig = try Config.targetFromEnvironment()
        guard sourceConfig.environment != targetConfig.environment else {
            throw CLIError.message("""
            Source and target are both '\(sourceConfig.environment)'. Set CLOUDKIT_ENVIRONMENT for the \
            source and CLOUDKIT_TARGET_ENVIRONMENT for the destination so they differ.
            """)
        }
        let source = try CloudKitS2SClient(config: sourceConfig)
        let target = try CloudKitS2SClient(config: targetConfig)

        print("copy-records: \(sourceConfig.environment) -> \(targetConfig.environment)  [\(sourceConfig.containerID)]\(dryRun ? "   (dry run — nothing written)" : "")")
        var totalCopied = 0, totalFailed = 0, totalAssetsSkipped = 0
        for type in types {
            let records: [CKRecordDTO]
            do {
                records = try await source.queryRecords(recordType: type)
            } catch {
                // A record type CloudKit has never seen a write for (e.g.
                // SportEvent, if this club has never had a plain non-
                // training/tournament event) doesn't exist in the schema at
                // all yet — the query 404s. That's "0 records", not a real
                // failure; don't abort the whole run over it.
                print("  \(type): 0 records (record type not in schema yet)")
                continue
            }
            if records.isEmpty {
                print("  \(type): 0 records")
                continue
            }
            if dryRun {
                print("  \(type): \(records.count) records would be copied")
                totalCopied += records.count
                continue
            }
            var ok = 0, failed = 0
            for record in records {
                var fields: [String: Any] = [:]
                var droppedAsset = false
                for (key, value) in record.fields {
                    if key.hasPrefix("_") { continue }               // server-managed
                    if (value as? [String: Any])?["type"] as? String == "ASSET" {
                        droppedAsset = true
                        continue
                    }
                    fields[key] = value
                }
                do {
                    _ = try await target.createOrReplaceRecord(recordType: type, recordName: record.recordName, fields: fields)
                    ok += 1
                    if droppedAsset { totalAssetsSkipped += 1 }
                } catch {
                    failed += 1
                    FileHandle.standardError.write("  ! \(type)/\(record.recordName): \(error)\n".data(using: .utf8)!)
                }
            }
            print("  \(type): \(ok) copied\(failed > 0 ? ", \(failed) failed" : "")")
            totalCopied += ok
            totalFailed += failed
        }
        if dryRun {
            print("Dry run: \(totalCopied) records across \(types.count) type(s).")
        } else {
            let assetNote = totalAssetsSkipped > 0 ? "  (\(totalAssetsSkipped) asset field(s) skipped — re-upload separately)" : ""
            print("Done: \(totalCopied) copied, \(totalFailed) failed.\(assetNote)")
        }
    }

    private static func recordJSON(id: String, fields: [String: Any]) throws -> String {
        var obj: [String: Any] = ["id": id]
        for (key, value) in CKFieldCoding.decode(fields) { obj[key] = value }
        let data = try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private static func printUsage() {
        print("""
        rootcli — manage BlindensportGraz accounts/roles (Supabase, service key)
        and the Grazer VSC roster directly in CloudKit (Server-to-Server auth).
        Does not require the app or an account in it.

        USAGE:
          rootcli list
          rootcli set-role <email|user id> <member|coach|admin|root>
          rootcli supabase-migrate [--dry-run|--apply]
          rootcli supabase-send-resets [--dry-run|--apply]
          rootcli supabase-scrub-cloudkit [--dry-run|--apply]
          rootcli import-members <file.json>
          rootcli update-members <file.json>
          rootcli record list <type>
          rootcli record get <type> <id>
          rootcli record set <type> <id> field=value [field:TYPE=value ...]
          rootcli record delete <type> <id>
          rootcli copy-records [--dry-run] [type ...]

        import-members reads a JSON array of members and creates/updates
        matching records in CloudKit (CKRecord type "ClubMember", the
        historical name kept for compatibility with already-synced data —
        see the app's Member model). "firstName" and "lastName" are
        required; see RootCLI/README.md and RootCLI/members.example.json for
        the schema. Matching existing records are fully overwritten with the
        file's data (blank fields in the file blank out the existing value too).

        update-members reads the same file shape but is non-destructive: for a
        person already in the roster (matched by firstName+lastName), it only
        fills fields that are currently blank and leaves existing data alone;
        people not yet in the roster are created as new ClubMember records.

        `record` is a generic insert/update/read/delete for ANY CloudKit record
        type this app publishes (UserIdentity, ClubMember, Team, TeamMembership,
        SportEvent, Training, Tournament, TrainingAttendance,
        TournamentAttendance, EventParticipation — not EventImage, which needs
        binary asset upload). `record set` always creates-or-updates (no
        conflict/change-tag handling, matching the app's own sync semantics).
        Field values default to STRING; use field:TYPE=value for INT64, DOUBLE,
        TIMESTAMP (ISO8601), or STRING_LIST (comma-separated). Example:
          rootcli record set Team 3F2504E0-... name="Herren A" sport=Torball
          rootcli record set UserIdentity 3F25... isRoot:INT64=1

        copy-records bulk-copies every record of the given types (default: all
        11 app types) from the source environment to a destination environment,
        preserving each record's id so cross-references (teamID, membershipID,
        …) stay valid. Upsert semantics. The destination needs its OWN
        Server-to-Server key (CloudKit requires a separate key pair per
        environment). Example — promote Development data to Production:
          CLOUDKIT_ENVIRONMENT=development CLOUDKIT_KEY_ID=<dev> CLOUDKIT_PRIVATE_KEY_PATH=<dev.pem> \\
          CLOUDKIT_TARGET_ENVIRONMENT=production CLOUDKIT_TARGET_KEY_ID=<prod> CLOUDKIT_TARGET_PRIVATE_KEY_PATH=<prod.pem> \\
          rootcli copy-records --dry-run

        list / set-role work on Supabase: set-role writes user_roles with the
        service key (logged as "System" in role_change_log; the last root can't
        be removed). supabase-migrate copies CloudKit accounts (same ids, email
        confirmed), effective roles (isRoot / designated club account → root),
        approvals and protected roster fields (svnr, iban, birthDate,
        lastMedicalExamination) to Supabase. supabase-send-resets emails every
        account a password-reset link. supabase-scrub-cloudkit removes the
        protected fields from ClubMember/MemberChangeRequest and deletes
        UserIdentity/RoleAssignment/AccountApproval records. All three are dry
        runs unless --apply.

        ENVIRONMENT:
          SUPABASE_URL                    Supabase project URL (https://<ref>.supabase.co)
          SUPABASE_SERVICE_KEY            service_role / sb_secret key — never commit, never ship in the app
          CLOUDKIT_CONTAINER              default: iCloud.it.a11y.BlindensportGraz
          CLOUDKIT_ENVIRONMENT            development | production (default: development)
          CLOUDKIT_KEY_ID                 required — Server-to-Server key id from CloudKit Dashboard
          CLOUDKIT_PRIVATE_KEY_PATH       required — path to the PKCS8 PEM private key
          CLOUDKIT_TARGET_ENVIRONMENT     copy-records destination (default: production)
          CLOUDKIT_TARGET_KEY_ID          copy-records destination — its own S2S key id
          CLOUDKIT_TARGET_PRIVATE_KEY_PATH  copy-records destination — its own PKCS8 PEM private key

        See RootCLI/README.md for one-time setup (key generation, Dashboard registration,
        and restricting write access to this key).
        """)
    }
}
