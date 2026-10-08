import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Minimal Supabase client for trusted tooling (rootcli, clubmembersapi):
/// GoTrue Admin API + PostgREST with the **service-role / secret key**,
/// which bypasses RLS. The key comes only from the environment
/// (`SUPABASE_URL`, `SUPABASE_SERVICE_KEY`) — never from a file in the repo,
/// and it must never be shipped in the iOS app.
public struct SupabaseAdminClient {
    public let baseURL: URL
    private let serviceKey: String
    private let session = URLSession(configuration: .ephemeral)

    public init(baseURL: URL, serviceKey: String) {
        self.baseURL = baseURL
        self.serviceKey = serviceKey
    }

    public static func fromEnvironment() throws -> SupabaseAdminClient {
        let env = ProcessInfo.processInfo.environment
        guard let raw = env["SUPABASE_URL"], let url = URL(string: raw), !raw.isEmpty else {
            throw CLIError.message("Missing SUPABASE_URL (e.g. https://<ref>.supabase.co). See RootCLI/README.md.")
        }
        guard let key = env["SUPABASE_SERVICE_KEY"], !key.isEmpty else {
            throw CLIError.message("Missing SUPABASE_SERVICE_KEY (service_role / sb_secret key). See RootCLI/README.md.")
        }
        return SupabaseAdminClient(baseURL: url, serviceKey: key)
    }

    // MARK: - Auth admin

    public struct AuthUser: Decodable {
        public let id: UUID
        public let email: String?
    }

    /// Creates a confirmed user with a fixed id (so existing CloudKit
    /// references to `User.id` keep working). Returns nil if the email is
    /// already registered.
    public func createUser(id: UUID, email: String, firstName: String, lastName: String) async throws -> AuthUser? {
        let body: [String: Any] = [
            "id": id.uuidString.lowercased(),
            "email": email,
            "email_confirm": true,
            "user_metadata": ["first_name": firstName, "last_name": lastName]
        ]
        let (data, status) = try await request("POST", "auth/v1/admin/users", json: body)
        if status == 422, String(decoding: data, as: UTF8.self).contains("already") { return nil }
        try check(status, data, "create user \(email)")
        return try JSONDecoder().decode(AuthUser.self, from: data)
    }

    public func listUsers() async throws -> [AuthUser] {
        struct Page: Decodable { let users: [AuthUser] }
        var all: [AuthUser] = []
        var page = 1
        while true {
            let (data, status) = try await request("GET", "auth/v1/admin/users",
                                                   query: [("page", "\(page)"), ("per_page", "1000")])
            try check(status, data, "list users")
            let users = try JSONDecoder().decode(Page.self, from: data).users
            all += users
            if users.count < 1000 { return all }
            page += 1
        }
    }

    /// Sends the standard "reset password" email (requires SMTP set up in
    /// the project; the built-in mailer is heavily rate-limited).
    public func sendPasswordReset(email: String, redirectTo: String) async throws {
        let (data, status) = try await request("POST", "auth/v1/recover",
                                               query: [("redirect_to", redirectTo)],
                                               json: ["email": email])
        try check(status, data, "password reset for \(email)")
    }

    // MARK: - PostgREST

    /// Insert-or-update rows (`resolution=merge-duplicates`), or with
    /// `ignoreDuplicates` insert only rows whose key doesn't exist yet.
    public func upsert(table: String, rows: [[String: Any]], onConflict: String,
                       ignoreDuplicates: Bool = false) async throws {
        guard !rows.isEmpty else { return }
        let resolution = ignoreDuplicates ? "ignore-duplicates" : "merge-duplicates"
        let (data, status) = try await request("POST", "rest/v1/\(table)",
                                               query: [("on_conflict", onConflict)],
                                               json: rows,
                                               headers: ["Prefer": "resolution=\(resolution),return=minimal"])
        try check(status, data, "upsert \(table)")
    }

    /// `filters` are PostgREST query items, e.g. ("id", "eq.<uuid>").
    public func update(table: String, filters: [(String, String)], values: [String: Any]) async throws {
        let (data, status) = try await request("PATCH", "rest/v1/\(table)", query: filters, json: values,
                                               headers: ["Prefer": "return=minimal"])
        try check(status, data, "update \(table)")
    }

    public func select(table: String, columns: String = "*", filters: [(String, String)] = []) async throws -> [[String: Any]] {
        let (data, status) = try await request("GET", "rest/v1/\(table)", query: [("select", columns)] + filters)
        try check(status, data, "select \(table)")
        return (try JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
    }

    public func rpc(_ name: String, params: [String: Any]) async throws -> Data {
        let (data, status) = try await request("POST", "rest/v1/rpc/\(name)", json: params)
        try check(status, data, "rpc \(name)")
        return data
    }

    // MARK: - Transport

    private func request(_ method: String, _ path: String, query: [(String, String)] = [],
                         json: Any? = nil, headers: [String: String] = [:]) async throws -> (Data, Int) {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query.map { URLQueryItem(name: $0.0, value: $0.1) } }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.setValue(serviceKey, forHTTPHeaderField: "apikey")
        // Legacy service_role keys are JWTs and also go in Authorization;
        // new sb_secret_ keys must only be sent as `apikey`.
        if serviceKey.hasPrefix("eyJ") {
            request.setValue("Bearer \(serviceKey)", forHTTPHeaderField: "Authorization")
        }
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        if let json {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: json)
        }
        let (data, response) = try await session.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    private func check(_ status: Int, _ data: Data, _ what: String) throws {
        guard (200..<300).contains(status) else {
            throw CLIError.message("Supabase \(what) failed (\(status)): \(String(decoding: data, as: UTF8.self))")
        }
    }
}
