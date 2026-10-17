import Foundation
import Observation
import Supabase
import SwiftData

/// The signed-in account, its role and permissions — the one place views ask
/// "may I…?" (`can(_:)`). Driven by Supabase `authStateChanges`; the role and
/// approval come from the access token's custom claims, so this is UI gating
/// only — RLS and the RPCs enforce the same rules server-side.
///
/// Also mirrors server state into the device-local SwiftData cache (`User`,
/// `AccountApproval`, `Member` private fields), which CloudKit no longer syncs.
@Observable
@MainActor
final class AuthContext {
    enum Phase: Equatable { case loading, signedOut, signedIn }

    private(set) var phase: Phase = .loading
    private(set) var claims: AccessClaims?
    private(set) var permissions: Set<Permission> = []
    private(set) var currentUser: User?
    /// Set when the app was opened from a password-reset link; the UI then
    /// asks for a new password.
    var isPasswordRecovery = false
    /// Last auth/deep-link error, for an alert.
    var lastError: String?
    /// True once this session's protected member data was loaded into the
    /// local cache — until then local svnr/iban/... are blank and must not
    /// be written back (`MemberPrivateSync`).
    private(set) var privateDataLoaded = false

    @ObservationIgnored private var modelContext: ModelContext?
    @ObservationIgnored private var listener: Task<Void, Never>?
    @ObservationIgnored private var appliedUserID: UUID?

    var role: AppRole? { claims?.role }
    /// Pending accounts (no role, no approval) only see the schedule.
    var hasFullAccess: Bool { claims?.approved ?? false }
    var isSignedIn: Bool { phase == .signedIn }

    func can(_ permission: Permission) -> Bool { permissions.contains(permission) }

    /// The app's single instance (set by `start`), for services without
    /// view context (`MemberPrivateSync`).
    static private(set) weak var current: AuthContext?

    /// Starts listening once; safe to call from every `.task`.
    func start(modelContext: ModelContext) {
        guard listener == nil else { return }
        AuthContext.current = self
        self.modelContext = modelContext
        guard SupabaseConfig.isConfigured else {
            phase = .signedOut
            return
        }
        listener = Task { [weak self] in
            for await change in SupabaseAuthService.authStateChanges {
                guard let self else { return }
                await self.handle(change.event, session: change.session)
            }
        }
    }

    /// Re-reads the token (e.g. after an approval or role change) so new
    /// claims apply without waiting for the regular refresh.
    func refresh() async {
        do { try await SupabaseAuthService.refreshSession() }
        catch { lastError = error.localizedDescription }
    }

    /// Re-pulls profiles, roles, approvals and private data into the local
    /// cache — after an admin action changed them on the server.
    func reload() async {
        guard let claims else { return }
        await mirrorServerState(for: claims)
    }

    func handleDeepLink(_ url: URL) async {
        guard SupabaseConfig.isAuthCallback(url) else { return }
        // verifyOTP reports a plain sign-in, so a recovery link opens the
        // "Neues Passwort" sheet here (old-style links via .passwordRecovery).
        do { if try await SupabaseAuthService.handleDeepLink(url) { isPasswordRecovery = true } }
        catch { lastError = String(localized: "Der Link ist ungültig oder abgelaufen.") }
    }

    func signOut() async {
        await PushRegistration.shared.unregister()
        try? await SupabaseAuthService.signOut()
    }

    // MARK: - State changes

    private func handle(_ event: AuthChangeEvent, session: Session?) async {
        if event == .passwordRecovery { isPasswordRecovery = true }

        // A stored session may be expired at launch (offline): keep showing
        // it — the SDK refreshes in the background and the server rejects
        // stale tokens anyway.
        guard event != .signedOut, let session,
              let decoded = AccessClaims.decode(jwt: session.accessToken) else {
            clear()
            return
        }

        // Routine refreshes (every ~15 min) with unchanged claims don't need
        // a full re-pull; `reload()` and pull-to-refresh cover admin edits.
        if event == .tokenRefreshed, decoded == claims, appliedUserID == decoded.userID {
            return
        }
        let roleChanged = decoded.role != claims?.role || appliedUserID != decoded.userID
        claims = decoded
        if roleChanged {
            if let table = try? await SupabaseRoleService.fetchPermissionTable() {
                Permission.serverTable = table
            }
            permissions = Permission.granted(to: decoded.role)
        }
        // Show the cached account right away (offline launch), then refresh
        // the cache from the server.
        if currentUser?.id != decoded.userID {
            currentUser = cachedUser(decoded.userID)
        }
        if currentUser != nil { phase = .signedIn }
        await mirrorServerState(for: decoded)
        phase = .signedIn
    }

    private func cachedUser(_ id: UUID) -> User? {
        guard let modelContext else { return nil }
        var descriptor = FetchDescriptor<User>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    private func clear() {
        claims = nil
        permissions = []
        privateDataLoaded = false
        currentUser = nil
        appliedUserID = nil
        UserDefaults.standard.removeObject(forKey: "localUserID")
        if let modelContext {
            SupabaseMemberPrivateService.applyToLocal(nil, modelContext: modelContext)
        }
        phase = .signedOut
    }

    /// Pulls what this account may see into the local cache. Network failures
    /// keep the previous cache (offline use).
    private func mirrorServerState(for claims: AccessClaims) async {
        guard let modelContext else { return }

        if let profile = try? await SupabaseProfileService.fetchProfile(userID: claims.userID) {
            currentUser = SupabaseProfileService.applyToLocalUser(
                profile, role: claims.role, modelContext: modelContext)
        } else if currentUser?.id != claims.userID {
            currentUser = cachedUser(claims.userID)
        }
        appliedUserID = claims.userID
        // Widget / App Intents read the current account from here.
        UserDefaults.standard.set(claims.userID.uuidString, forKey: "localUserID")

        if let directory = try? await SupabaseProfileService.fetchDirectory() {
            SupabaseProfileService.applyDirectory(directory, modelContext: modelContext)
        }
        if can(.usersApprove) {
            if let profiles = try? await SupabaseProfileService.fetchAllProfiles() {
                for profile in profiles {
                    SupabaseProfileService.applyToLocalUser(profile, role: nil, modelContext: modelContext)
                }
                // Accounts root deleted: approvers get every profile, so a
                // cached full account (with email) missing here is gone.
                // Demoted to a name-only row instead of deleted: App-Konten
                // hides rows without email, while a deleted model still on
                // screen (its row, menus) crashes SwiftData on the next read
                // (bug-554), and the cascade would drop local team
                // memberships/participations the next pull fixes anyway.
                let serverIDs = Set(profiles.map(\.id))
                let local = (try? modelContext.fetch(FetchDescriptor<User>())) ?? []
                for user in local where !user.email.isEmpty && user.id != claims.userID
                    && !serverIDs.contains(user.id) {
                    user.email = ""
                    user.calendarToken = ""
                    user.role = .member
                    user.isRoot = false
                }
                try? modelContext.save()
            }
        }
        if let roles = try? await SupabaseRoleService.fetchRoles() {
            SupabaseRoleService.applyToLocalUsers(roles, modelContext: modelContext)
        }
        if let approvals = try? await SupabaseApprovalService.fetchAll() {
            SupabaseApprovalService.applyToLocal(approvals, modelContext: modelContext)
        }
        // RLS returns all rows for admins, the own row for approved members,
        // nothing otherwise — the local cache is overwritten to match.
        if let rows = try? await SupabaseMemberPrivateService.fetchAll() {
            SupabaseMemberPrivateService.applyToLocal(rows, modelContext: modelContext)
            privateDataLoaded = true
        }
    }
}
