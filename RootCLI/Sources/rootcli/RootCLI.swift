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
            try await runSetRole(rest)
        case "set-root":
            try await runSetRoot(rest)
        case "import-members":
            try await runImportMembers(rest)
        case "record":
            try await runRecord(rest)
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
        let client = try makeClient()
        let users = try await client.queryRecords(recordType: "UserIdentity")
        guard !users.isEmpty else {
            print("No UserIdentity records found.")
            return
        }
        let sorted = users.sorted { fullName($0) < fullName($1) }

        func pad(_ text: String, _ width: Int) -> String {
            text.count >= width ? String(text.prefix(width - 1)) + " " : text.padding(toLength: width, withPad: " ", startingAt: 0)
        }

        print(pad("Name", 28) + pad("Role", 9) + pad("Root", 6) + "Email")
        for user in sorted {
            let name = fullName(user)
            let role = user.stringField("role") ?? "member"
            let root = user.boolField("isRoot") ? "yes" : ""
            print(pad(name, 28) + pad(role, 9) + pad(root, 6) + "n/a — email is never synced to CloudKit, see RootCLI/README.md")
        }
    }

    /// Joins a UserIdentity record's firstName/lastName fields, matching
    /// User.displayName's own formatting in the app (Models.swift).
    private static func fullName(_ user: CKRecordDTO) -> String {
        let name = [user.stringField("firstName") ?? "", user.stringField("lastName") ?? ""]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return name.isEmpty ? "?" : name
    }

    private static func runSetRole(_ args: [String]) async throws {
        guard args.count == 2 else {
            throw CLIError.message("Usage: rootcli set-role <full name|id> <member|coach|admin>")
        }
        let identifier = args[0]
        let role = args[1]
        guard ["member", "coach", "admin"].contains(role) else {
            throw CLIError.message("Role must be one of: member, coach, admin")
        }
        let client = try makeClient()
        let user = try await client.findUser(matching: identifier)
        try await client.updateRecord(user, fields: ["role": ["value": role]])
        print("Updated \(fullName(user)): role -> \(role)")
    }

    private static func runSetRoot(_ args: [String]) async throws {
        guard args.count == 2, let flag = Bool(args[1].lowercased()) else {
            throw CLIError.message("Usage: rootcli set-root <full name|id> <true|false>")
        }
        let identifier = args[0]
        let client = try makeClient()
        let user = try await client.findUser(matching: identifier)
        try await client.updateRecord(user, fields: ["isRoot": ["value": flag ? 1 : 0, "type": "INT64"]])
        print("Updated \(fullName(user)): isRoot -> \(flag)")
    }

    private static func runImportMembers(_ args: [String]) async throws {
        guard args.count == 1 else {
            throw CLIError.message("Usage: rootcli import-members <file.json>")
        }
        let inputs = try ClubMemberImport.loadRecords(from: args[0])
        guard !inputs.isEmpty else {
            print("No members found in \(args[0]).")
            return
        }

        let client = try makeClient()
        var succeeded = 0
        var failed = 0

        for input in inputs {
            let firstName = (input.firstName ?? "").trimmingCharacters(in: .whitespaces)
            let lastName = (input.lastName ?? "").trimmingCharacters(in: .whitespaces)
            let fullName = [firstName, lastName].filter { !$0.isEmpty }.joined(separator: " ")
            guard !firstName.isEmpty, !lastName.isEmpty else {
                print("Skipped an entry with an empty firstName or lastName.")
                failed += 1
                continue
            }

            let recordName: String
            if let providedID = input.id {
                guard UUID(uuidString: providedID) != nil else {
                    print("Skipped \(fullName): id '\(providedID)' is not a valid UUID (the app only reads UUID record names).")
                    failed += 1
                    continue
                }
                recordName = providedID
            } else {
                recordName = UUID().uuidString
            }

            let record = ClubMemberRecord(
                id: recordName,
                firstName: firstName,
                lastName: lastName,
                street: input.street ?? "",
                zip: input.zip ?? "",
                city: input.city ?? "",
                email: input.email ?? "",
                phone: input.phone ?? "",
                memberNumber: input.memberNumber ?? "",
                joinedAt: ClubMemberImport.parseJoinedAt(input.joinedAt) ?? Date(),
                notes: input.notes ?? ""
            )

            do {
                try await client.createOrReplaceRecord(recordType: "ClubMember", recordName: recordName, fields: record.ckFields)
                print("Imported \(fullName) (\(recordName))")
                succeeded += 1
            } catch {
                print("Failed to import \(fullName): \(error)")
                failed += 1
            }
        }

        print("Done: \(succeeded) imported, \(failed) failed, out of \(inputs.count).")
    }

    /// Generic insert/update/read/delete for ANY CloudKit record type this
    /// app publishes — not just ClubMember. Unlike `set-role`/`set-root`
    /// (which hand-decode specific fields of one specific type) or
    /// `import-members` (which mirrors `ClubMemberRecord`), this works
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
                throw CLIError.message("Usage: rootcli record set <type> <id> field=value [field:TYPE=value ...]\nTYPE is one of INT64, DOUBLE, TIMESTAMP, STRING_LIST, STRING (default STRING when omitted).")
            }
            let recordType = rest[0]
            let id = rest[1]
            let assignments = Array(rest.dropFirst(2))
            let fields = CKFieldCoding.parseCLIAssignments(assignments)
            guard !fields.isEmpty else {
                throw CLIError.message("No valid field=value assignments given.")
            }
            try await client.createOrReplaceRecord(recordType: recordType, recordName: id, fields: fields)
            print("Upserted \(recordType) \(id): \(assignments.joined(separator: ", "))")

        case "delete":
            guard rest.count == 2 else {
                throw CLIError.message("Usage: rootcli record delete <type> <id>")
            }
            try await client.deleteRecord(recordType: rest[0], recordName: rest[1])
            print("Deleted \(rest[0]) \(rest[1]).")

        default:
            throw CLIError.message("Unknown record subcommand '\(sub)'. Use list, get, set, or delete.")
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
        rootcli — manage BlindensportGraz user roles and the Grazer VSC roster
        directly in CloudKit, via Server-to-Server auth. Does not require the
        app or an account in it.

        USAGE:
          rootcli list
          rootcli set-role <full name|id> <member|coach|admin>
          rootcli set-root <full name|id> <true|false>
          rootcli import-members <file.json>
          rootcli record list <type>
          rootcli record get <type> <id>
          rootcli record set <type> <id> field=value [field:TYPE=value ...]
          rootcli record delete <type> <id>

        import-members reads a JSON array of club members and creates/updates
        matching ClubMember records in CloudKit. "firstName" and "lastName" are
        required; see RootCLI/README.md and RootCLI/members.example.json for
        the schema.

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

        ENVIRONMENT:
          CLOUDKIT_CONTAINER          default: iCloud.it.a11y.BlindensportGraz
          CLOUDKIT_ENVIRONMENT        development | production (default: development)
          CLOUDKIT_KEY_ID             required — Server-to-Server key id from CloudKit Dashboard
          CLOUDKIT_PRIVATE_KEY_PATH   required — path to the PKCS8 PEM private key

        See RootCLI/README.md for one-time setup (key generation, Dashboard registration,
        and restricting write access to this key).
        """)
    }
}
