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

    private static func printUsage() {
        print("""
        rootcli — manage BlindensportGraz user roles directly in CloudKit, via
        Server-to-Server auth. Does not require the app or an account in it.

        USAGE:
          rootcli list
          rootcli set-role <username|displayName|id> <member|coach|admin>
          rootcli set-root <username|displayName|id> <true|false>

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
