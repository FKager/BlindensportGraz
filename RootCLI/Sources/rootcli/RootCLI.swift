import Foundation

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
        let sorted = users.sorted { ($0.stringField("displayName") ?? "") < ($1.stringField("displayName") ?? "") }

        func pad(_ text: String, _ width: Int) -> String {
            text.count >= width ? String(text.prefix(width - 1)) + " " : text.padding(toLength: width, withPad: " ", startingAt: 0)
        }

        print(pad("Name", 28) + pad("Username", 20) + pad("Role", 9) + pad("Root", 6) + "Email")
        for user in sorted {
            let name = user.stringField("displayName") ?? "?"
            let username = "@" + (user.stringField("username") ?? "?")
            let role = user.stringField("role") ?? "member"
            let root = user.boolField("isRoot") ? "yes" : ""
            print(pad(name, 28) + pad(username, 20) + pad(role, 9) + pad(root, 6) + "n/a — email is never synced to CloudKit, see RootCLI/README.md")
        }
    }

    private static func runSetRole(_ args: [String]) async throws {
        guard args.count == 2 else {
            throw CLIError.message("Usage: rootcli set-role <username|displayName|id> <member|coach|admin>")
        }
        let identifier = args[0]
        let role = args[1]
        guard ["member", "coach", "admin"].contains(role) else {
            throw CLIError.message("Role must be one of: member, coach, admin")
        }
        let client = try makeClient()
        let user = try await client.findUser(matching: identifier)
        try await client.updateRecord(user, fields: ["role": ["value": role]])
        print("Updated @\(user.stringField("username") ?? identifier): role -> \(role)")
    }

    private static func runSetRoot(_ args: [String]) async throws {
        guard args.count == 2, let flag = Bool(args[1].lowercased()) else {
            throw CLIError.message("Usage: rootcli set-root <username|displayName|id> <true|false>")
        }
        let identifier = args[0]
        let client = try makeClient()
        let user = try await client.findUser(matching: identifier)
        try await client.updateRecord(user, fields: ["isRoot": ["value": flag ? 1 : 0, "type": "INT64"]])
        print("Updated @\(user.stringField("username") ?? identifier): isRoot -> \(flag)")
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

            let joinedAt = ClubMemberImport.parseJoinedAt(input.joinedAt) ?? Date()
            let fields: [String: Any] = [
                "firstName": ["value": firstName],
                "lastName": ["value": lastName],
                "street": ["value": input.street ?? ""],
                "zip": ["value": input.zip ?? ""],
                "city": ["value": input.city ?? ""],
                "email": ["value": input.email ?? ""],
                "phone": ["value": input.phone ?? ""],
                "memberNumber": ["value": input.memberNumber ?? ""],
                "notes": ["value": input.notes ?? ""],
                "joinedAt": ["value": Int64(joinedAt.timeIntervalSince1970 * 1000), "type": "TIMESTAMP"]
            ]

            do {
                try await client.createOrReplaceRecord(recordType: "ClubMember", recordName: recordName, fields: fields)
                print("Imported \(fullName) (\(recordName))")
                succeeded += 1
            } catch {
                print("Failed to import \(fullName): \(error)")
                failed += 1
            }
        }

        print("Done: \(succeeded) imported, \(failed) failed, out of \(inputs.count).")
    }

    private static func printUsage() {
        print("""
        rootcli — manage BlindensportGraz user roles and the Grazer VSC roster
        directly in CloudKit, via Server-to-Server auth. Does not require the
        app or an account in it.

        USAGE:
          rootcli list
          rootcli set-role <username|displayName|id> <member|coach|admin>
          rootcli set-root <username|displayName|id> <true|false>
          rootcli import-members <file.json>

        import-members reads a JSON array of club members and creates/updates
        matching ClubMember records in CloudKit. "firstName" and "lastName" are
        required; see RootCLI/README.md and RootCLI/members.example.json for
        the schema.

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
