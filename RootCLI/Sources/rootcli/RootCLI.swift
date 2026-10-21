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
        case "supabase-send-resets":
            try await SupabaseMigrate.runSendResets(rest)
        case "import-members":
            try await runImportMembers(rest)
        case "update-members":
            try await runUpdateMembers(rest)
        case "-h", "--help", "help":
            printUsage()
        default:
            throw CLIError.message("Unknown command '\(command)'. Run `rootcli help` for usage.")
        }
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

        let store = MemberStore(supabase: try SupabaseAdminClient.fromEnvironment())
        let result = await MemberBulkImport.run(inputs, store: store)
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

        let store = MemberStore(supabase: try SupabaseAdminClient.fromEnvironment())
        let result = await MemberFillUpdate.run(inputs, store: store)
        for message in result.messages { print(message) }
        print("Done: \(result.succeeded) updated/created, \(result.failed) failed, out of \(inputs.count).")
    }

    private static func printUsage() {
        print("""
        rootcli — manage BlindensportGraz accounts, roles and the Grazer VSC
        roster in Supabase (service key). Does not require the app or an
        account in it.

        USAGE:
          rootcli list
          rootcli set-role <email|user id> <member|coach|admin|root>
          rootcli supabase-send-resets [--dry-run|--apply]
          rootcli import-members <file.json>
          rootcli update-members <file.json>

        list shows every account with its role and approval. set-role writes
        user_roles (logged as "System" in role_change_log; the last root can't
        be removed). supabase-send-resets emails every account a password-reset
        link (dry run unless --apply).

        import-members reads a JSON array of members and creates/updates the
        matching roster entries (members, member_contacts, member_private).
        "firstName" and "lastName" are required; see RootCLI/README.md and
        RootCLI/members.example.json for the schema. Matching entries are fully
        overwritten (blank fields in the file blank out the existing value too).

        update-members reads the same file shape but is non-destructive: for a
        person already in the roster (matched by firstName+lastName), it only
        fills fields that are currently blank; people not yet in the roster are
        created.

        ENVIRONMENT:
          SUPABASE_URL           Supabase project URL (https://<ref>.supabase.co)
          SUPABASE_SERVICE_KEY   service_role / sb_secret key — never commit, never ship in the app
        """)
    }
}
