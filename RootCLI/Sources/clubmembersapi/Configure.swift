import Vapor
import CloudKitS2SCore

func configure(_ app: Application) throws {
    let cloudKitConfig = try Config.fromEnvironment()
    let client = try CloudKitS2SClient(config: cloudKitConfig)

    // Basic Auth gate. This server holds a CloudKit S2S key that can read/write
    // every club member's PII (address, phone, email) — see RootCLI/README.md's
    // warning about that key. Both the API and the static admin page below sit
    // behind these credentials by default; there is no "no auth" mode.
    let env = ProcessInfo.processInfo.environment
    guard let apiUsername = env["API_USERNAME"], !apiUsername.isEmpty,
          let apiPassword = env["API_PASSWORD"], !apiPassword.isEmpty else {
        throw CLIError.message("""
            Missing required environment variables API_USERNAME / API_PASSWORD.
            clubmembersapi always requires HTTP Basic Auth credentials — it has no \
            unauthenticated mode, since it exposes club members' address/phone/email. \
            See RootCLI/README.md.
            """)
    }

    app.middleware.use(ClubMembersAuthenticator(username: apiUsername, password: apiPassword))
    app.middleware.use(APIUser.guardMiddleware())
    app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory, defaultFile: "index.html"))

    if let portString = env["PORT"], let port = Int(portString) {
        app.http.server.configuration.port = port
    }
    if let hostname = env["HOSTNAME"] {
        app.http.server.configuration.hostname = hostname
    }

    try routes(app, client: client)
}
