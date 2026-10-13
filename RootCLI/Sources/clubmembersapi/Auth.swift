import Vapor
import CloudKitS2SCore

/// A signed-in club admin. Accounts, roles and permissions come from
/// Supabase (the same ones the app uses) — there is no shared server
/// password any more. `permissions` are the `app_permission` values of the
/// account's role, re-read from the database every few minutes
/// (`AdminSessionStore.recheckInterval`), so a role change or removal
/// reaches an open browser session quickly.
struct AdminUser: Authenticatable {
    let id: UUID
    let email: String
    let role: String
    let permissions: Set<String>

    func require(_ permission: String) throws {
        guard permissions.contains(permission) else {
            throw Abort(.forbidden, reason: "Keine Berechtigung (\(permission)).")
        }
    }
}

extension Request {
    /// The signed-in admin; `RequireAdminForAPI` guarantees one on /api.
    func admin() throws -> AdminUser {
        guard let user = auth.get(AdminUser.self) else { throw Abort(.unauthorized) }
        return user
    }
}

/// In-memory sessions: an opaque random token in an HttpOnly cookie maps to
/// the admin. Nothing secret is kept after login (the Supabase tokens from
/// the password check are discarded). A restart signs everyone out, which is
/// fine for a handful of admins.
actor AdminSessionStore {
    struct Entry {
        var user: AdminUser
        let created: Date
        var lastSeen: Date
        var lastChecked: Date
    }

    static let idleTimeout: TimeInterval = 30 * 60
    static let absoluteTimeout: TimeInterval = 12 * 60 * 60
    static let recheckInterval: TimeInterval = 5 * 60

    private var sessions: [String: Entry] = [:]
    private let supabase: SupabaseAdminClient

    init(supabase: SupabaseAdminClient) {
        self.supabase = supabase
    }

    func create(_ user: AdminUser) -> String {
        let now = Date()
        // Sessions are otherwise only expired when their token is presented
        // again; drop abandoned ones here so the dictionary stays bounded.
        sessions = sessions.filter { !Self.isExpired($0.value, at: now) }
        let token = [UInt8].random(count: 32).map { String(format: "%02x", $0) }.joined()
        sessions[token] = Entry(user: user, created: now, lastSeen: now, lastChecked: now)
        return token
    }

    /// The session's admin, or nil if unknown, expired, or no longer allowed
    /// to use the admin tool (role removed or downgraded).
    func user(for token: String) async -> AdminUser? {
        guard let entry = sessions[token] else { return nil }
        let now = Date()
        guard !Self.isExpired(entry, at: now) else {
            sessions[token] = nil
            return nil
        }
        if now.timeIntervalSince(entry.lastChecked) >= Self.recheckInterval {
            let access = try? await supabase.access(for: entry.user.id)
            // Actor reentrancy: while we awaited, the session may have been
            // signed out, or a concurrent request may have finished a newer
            // recheck — never write an older result over either.
            guard var current = sessions[token] else { return nil }
            if current.lastChecked > entry.lastChecked {
                current.lastSeen = now
                sessions[token] = current
                return current.user
            }
            guard let access, let role = access.role,
                  access.permissions.contains(AdminLogin.requiredPermission) else {
                sessions[token] = nil
                return nil
            }
            current.user = AdminUser(id: entry.user.id, email: entry.user.email, role: role,
                                     permissions: access.permissions)
            current.lastChecked = now
            current.lastSeen = now
            sessions[token] = current
            return current.user
        }
        var updated = entry
        updated.lastSeen = now
        sessions[token] = updated
        return updated.user
    }

    private static func isExpired(_ entry: Entry, at now: Date) -> Bool {
        now.timeIntervalSince(entry.lastSeen) >= idleTimeout
            || now.timeIntervalSince(entry.created) >= absoluteTimeout
    }

    func remove(_ token: String) {
        sessions[token] = nil
    }
}

/// Reads the session cookie and logs the admin in for this request.
struct AdminSessionAuthenticator: AsyncRequestAuthenticator {
    let store: AdminSessionStore

    func authenticate(request: Request) async throws {
        guard let token = request.cookies[AdminLogin.cookieName]?.string, !token.isEmpty,
              let user = await store.user(for: token) else { return }
        request.auth.login(user)
    }
}

/// Everything under /api needs a signed-in admin, except signing in itself.
/// Static pages (index.html, records.html) contain no data and stay public so
/// they can show the sign-in form; `/calendar/*` has its own per-user token
/// (see CalendarFeedRoutes.swift).
///
/// Changing requests must also carry `X-Requested-With: blindensport-admin`.
/// Together with the SameSite=Strict cookie this blocks cross-site request
/// forgery: a foreign page can't set custom headers without a CORS
/// preflight, which this server never answers.
struct RequireAdminForAPI: AsyncMiddleware {
    static let csrfHeader = "X-Requested-With"
    static let csrfValue = "blindensport-admin"

    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        let path = request.url.path
        guard path == "/api" || path.hasPrefix("/api/") else {
            return try await next.respond(to: request)
        }
        if request.method != .GET, request.headers.first(name: Self.csrfHeader) != Self.csrfValue {
            throw Abort(.forbidden, reason: "Missing \(Self.csrfHeader) header.")
        }
        if path == "/api/session" {
            return try await next.respond(to: request)
        }
        guard request.auth.has(AdminUser.self) else {
            throw Abort(.unauthorized, reason: "Bitte anmelden.")
        }
        return try await next.respond(to: request)
    }
}

/// POST/GET/DELETE /api/session — sign in with a Supabase account, show
/// the current admin, sign out.
enum AdminLogin {
    static let cookieName = "bsg_admin_session"
    /// Minimum to use the admin tool at all; individual routes check more.
    static let requiredPermission = "members.manage"

    struct Credentials: Content {
        var email: String
        var password: String
    }

    struct SessionInfo: Content {
        var email: String
        var role: String
        var permissions: [String]
    }

    static func routes(_ app: RoutesBuilder, supabase: SupabaseAdminClient, store: AdminSessionStore,
                       limiter: LoginAttemptLimiter, secureCookie: Bool) {
        let session = app.grouped("api", "session")

        session.post { req async throws -> Response in
            let client = clientAddress(for: req)
            guard await !limiter.isLockedOut(client: client) else {
                throw Abort(.tooManyRequests, reason: "Zu viele Fehlversuche. Bitte später erneut versuchen.")
            }
            let credentials = try req.content.decode(Credentials.self)
            let email = credentials.email.trimmingCharacters(in: .whitespaces).lowercased()
            guard let account = try await supabase.verifyPassword(email: email, password: credentials.password) else {
                await limiter.recordFailure(client: client)
                throw Abort(.unauthorized, reason: "E-Mail oder Passwort falsch.")
            }
            let access = try await supabase.access(for: account.id)
            guard let role = access.role, access.permissions.contains(requiredPermission) else {
                req.logger.notice("Admin sign-in refused for \(email): role \(access.role ?? "pending")")
                throw Abort(.forbidden, reason: "Dieses Konto hat keinen Zugriff auf die Mitgliederverwaltung.")
            }
            // Only an admin sign-in clears the failure history: any member's
            // correct password must not reset the brute-force window.
            await limiter.recordSuccess(client: client)
            let user = AdminUser(id: account.id, email: account.email ?? email, role: role,
                                 permissions: access.permissions)
            let token = await store.create(user)
            req.logger.info("Admin signed in: \(user.email) (\(role))")

            let response = try await info(user).encodeResponse(for: req)
            response.cookies[cookieName] = HTTPCookies.Value(
                string: token, maxAge: Int(AdminSessionStore.absoluteTimeout), path: "/",
                isSecure: secureCookie, isHTTPOnly: true, sameSite: .strict)
            return response
        }

        session.get { req async throws -> SessionInfo in
            guard let user = req.auth.get(AdminUser.self) else { throw Abort(.unauthorized, reason: "Bitte anmelden.") }
            return info(user)
        }

        session.delete { req async throws -> Response in
            if let token = req.cookies[cookieName]?.string { await store.remove(token) }
            let response = Response(status: .noContent)
            response.cookies[cookieName] = HTTPCookies.Value(
                string: "", expires: Date(timeIntervalSince1970: 0), path: "/",
                isSecure: secureCookie, isHTTPOnly: true, sameSite: .strict)
            return response
        }
    }

    private static func info(_ user: AdminUser) -> SessionInfo {
        SessionInfo(email: user.email, role: user.role, permissions: user.permissions.sorted())
    }

    /// `LoginAttemptLimiter`'s rate-limit key. Prefers the first hop of
    /// `X-Forwarded-For` over the raw TCP peer address — necessary once this
    /// server runs behind the bundled Caddy reverse proxy (see
    /// docker-compose.yml/Caddyfile at the repo root): without this,
    /// `request.remoteAddress` would always be Caddy's own container IP, so
    /// every real client would share one failure-count bucket.
    ///
    /// Safe to trust the header unconditionally here ONLY because
    /// docker-compose.yml does not publish `clubmembersapi`'s port to the
    /// host or the internet — the sole path to this process is through the
    /// `caddy` container. **If this binary is ever run WITHOUT that bundled
    /// Caddy in front of it, this header becomes attacker-controlled** — see
    /// RootCLI/README.md's "Deployment / TLS" section.
    static func clientAddress(for request: Request) -> String {
        if let forwardedFor = request.headers.first(name: "X-Forwarded-For") {
            let firstHop = forwardedFor.split(separator: ",").first?.trimmingCharacters(in: .whitespaces)
            if let firstHop, !firstHop.isEmpty { return firstHop }
        }
        return request.remoteAddress?.ipAddress ?? "unknown"
    }
}
