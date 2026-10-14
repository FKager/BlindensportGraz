import Vapor
import CloudKitS2SCore

func configure(_ app: Application) throws {
    // All club data lives in Supabase; this server uses the service key, so
    // it must check each admin's permissions itself (see Auth.swift and
    // Routes.swift).
    let supabase = try SupabaseAdminClient.fromEnvironment()
    let sessions = AdminSessionStore(supabase: supabase)

    let env = ProcessInfo.processInfo.environment
    // The session cookie is Secure by default (Caddy terminates TLS in front
    // of this server). Only for local testing over plain http://localhost:
    // SESSION_COOKIE_SECURE=false.
    let secureCookie = env["SESSION_COOKIE_SECURE"]?.lowercased() != "false"

    app.middleware.use(AdminSessionAuthenticator(store: sessions))
    app.middleware.use(RequireAdminForAPI())
    app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory, defaultFile: "index.html"))

    if let portString = env["PORT"], let port = Int(portString) {
        app.http.server.configuration.port = port
    }
    if let hostname = env["HOSTNAME"] {
        app.http.server.configuration.hostname = hostname
    }

    AdminLogin.routes(app, supabase: supabase, store: sessions, limiter: LoginAttemptLimiter(),
                      secureCookie: secureCookie)
    calendarFeedRoutes(app, supabase: supabase)
    try routes(app, store: MemberStore(supabase: supabase))
}
