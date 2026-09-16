import SwiftUI
import SwiftData
import AuthenticationServices

/// Records that the club's designated-root account was created or logged into
/// on *this* device, so `LoginView` keeps offering it here while hiding it on
/// every other device it merely synced to. No-op for any other account.
func rememberLocalDesignatedRoot(_ user: User) {
    guard user.isDesignatedRootIdentity else { return }
    UserDefaults.standard.set(user.id.uuidString, forKey: User.localDesignatedRootIDKey)
}

struct RootView: View {
    @State private var currentUser: User?
    @State private var isResolvingAccount = true
    @AppStorage("appleUserIdentifier") private var storedAppleUserIdentifier = ""
    // appleUserIdentifier is deliberately never synced to CloudKit (privacy —
    // stays device-local), so if the local store is ever wiped and rebuilt
    // from a CloudKit resync (see BlindensportGrazApp's ModelContainer
    // migration fallback), the freshly-pulled User row has no
    // appleUserIdentifier to match against on this device anymore. This
    // second key remembers the local `id` (which CloudKit does carry) so
    // resolveAccount can re-link to the same synced account instead of
    // silently minting a duplicate one below.
    @AppStorage("localUserID") private var storedUserID = ""

    @Environment(\.modelContext) private var modelContext
    // Intentionally unfiltered (audit.md SwiftData & CloudKit Finding 6):
    // resolveAccount() below needs to search every User for an
    // appleUserIdentifier/id match, and check `users.isEmpty` for the
    // very-first-account bootstrap — there's no subset of users that would
    // still answer either question correctly.
    @Query private var users: [User]

    private let appleSignIn = AppleSignInCoordinator()

    var body: some View {
        Group {
            if isResolvingAccount {
                ProgressView()
            } else if let user = currentUser {
                MainTabView(currentUser: user, onLogout: {
                    // Clears the same two @AppStorage keys resolveAccount()
                    // resumes from — logout used to leave these set, which
                    // is exactly the class of bug self-delete (AccountView)
                    // would otherwise reintroduce (next launch tries to
                    // "resume" an account that's gone / was just logged out
                    // of, per cerebrum's bug-164/bug-373 notes).
                    storedAppleUserIdentifier = ""
                    storedUserID = ""
                    currentUser = nil
                })
            } else {
                AnonymousLandingView(onLogin: onLogin, onAppleSignIn: { await performAppleSignIn() })
            }
        }
        .task {
            await resolveAccount()
        }
    }

    /// Resumes a previously-resolved account from `@AppStorage` if there is
    /// one. Otherwise leaves `currentUser` nil (anonymous) rather than
    /// auto-firing Apple's sign-in sheet — Sign in with Apple is now an
    /// explicit "Mit Apple anmelden" button in LoginView (see
    /// `performAppleSignIn()`), not something that ambushes a fresh install
    /// before the person has chosen to register/log in (account-tiers
    /// refactor). Still syncs in the background either way, so the
    /// anonymous landing screen's "next event" preview has real data.
    private func resolveAccount() async {
        defer { isResolvingAccount = false }

        if !storedAppleUserIdentifier.isEmpty {
            if let match = users.first(where: { $0.appleUserIdentifier == storedAppleUserIdentifier }) {
                currentUser = match
                storedUserID = match.id.uuidString
                applyDesignatedRootGrant(match)
                rememberLocalDesignatedRoot(match)
            } else if !storedUserID.isEmpty, let id = UUID(uuidString: storedUserID) {
                currentUser = users.first { $0.id == id }
                if let resumed = currentUser {
                    applyDesignatedRootGrant(resumed)
                    rememberLocalDesignatedRoot(resumed)
                }
            }
            triggerBackgroundSync()
            return
        }

        triggerAnonymousBackgroundSync()
    }

    /// Sign in with Apple, on demand — called from LoginView's "Mit Apple
    /// anmelden" button, and no longer automatically on every fresh launch
    /// (see `resolveAccount()`'s doc comment). Mints a brand-new `User` from
    /// whatever Apple provided if this Apple ID has never signed in before.
    private func performAppleSignIn() async {
        guard let result = try? await appleSignIn.requestSignIn() else { return }

        if let existing = users.first(where: { $0.appleUserIdentifier == result.userIdentifier }) {
            storedAppleUserIdentifier = result.userIdentifier
            storedUserID = existing.id.uuidString
            currentUser = existing
            applyDesignatedRootGrant(existing)
            triggerBackgroundSync()
            return
        }

        // Apple only sends a real email/fullName on the very first grant for
        // this Apple ID + bundle/team combo — never again, not even after an
        // app uninstall+reinstall (see cerebrum's 2026-07-15 Apple Sign-In
        // note). A blank result here, with no local storedAppleUserIdentifier/
        // storedUserID match either (both @AppStorage, wiped by the same
        // uninstall that wipes the local SwiftData store — see bug-164),
        // means this device almost certainly already has a real account
        // somewhere in CloudKit, we just lost every local pointer to it.
        // appleUserIdentifier is deliberately never synced to CloudKit (see
        // this struct's doc comment above), so there is no remote field left
        // to match against — silently minting a blank "Neues Mitglied"
        // account here would orphan the real one instead of asking. Sync
        // first so the real account is pulled in, then bail out to
        // LoginView's account picker instead of guessing.
        if result.fullName == nil && (result.email?.isEmpty ?? true) {
            await SyncOrchestrationService.syncAll(modelContext: modelContext)
            return
        }

        let appleFirstName = result.fullName?.givenName?.trimmingCharacters(in: .whitespaces) ?? ""
        let appleLastName = result.fullName?.familyName?.trimmingCharacters(in: .whitespaces) ?? ""
        let emailPrefix = result.email?.components(separatedBy: "@").first ?? ""
        let firstName: String
        let lastName: String
        if !appleFirstName.isEmpty || !appleLastName.isEmpty {
            firstName = appleFirstName
            lastName = appleLastName
        } else if !emailPrefix.isEmpty {
            firstName = emailPrefix
            lastName = ""
        } else {
            firstName = "Neues"
            lastName = "Mitglied"
        }

        let user = User(email: result.email ?? "",
                         firstName: firstName,
                         lastName: lastName,
                         appleUserIdentifier: result.userIdentifier)
        // The very first account ever created (locally and in CloudKit) becomes root,
        // and admin too — otherwise it'd be locked out of the admin features it needs
        // to set up the club (teams, roster, other admins) in the first place.
        if users.isEmpty, !(await SyncOrchestrationService.hasAnyUserIdentity()) {
            user.isRoot = true
            user.role = .admin
        }
        let oldRole = user.role
        let becameDesignatedRoot = user.elevateIfDesignatedRoot()
        modelContext.insert(user)
        Member.checkMembership(for: user, modelContext: modelContext)
        UserService.save(user, modelContext: modelContext)
        if becameDesignatedRoot {
            RoleChangeLogService.log(userID: user.id, oldRole: oldRole.rawValue, newRole: user.role.rawValue,
                                      changedBy: "system:designatedRoot", modelContext: modelContext)
        }

        storedAppleUserIdentifier = result.userIdentifier
        storedUserID = user.id.uuidString
        rememberLocalDesignatedRoot(user)
        currentUser = user
        triggerBackgroundSync()
    }

    /// Shared completion for every non-Apple login path — LoginView's
    /// email+password form (including its "Passwort festlegen" migration
    /// flow) and RegisterView's account creation, both reached from
    /// AnonymousLandingView. Apple Sign-In has its own completion inside
    /// `performAppleSignIn()`/`resolveAccount()` above (it sets
    /// `storedAppleUserIdentifier` too, which these paths never have).
    private func onLogin(_ user: User) {
        applyDesignatedRootGrant(user)
        // Picking an existing account or finishing RegisterView counts as
        // "entered on this device" — keep offering the designated-root
        // account here afterwards (see LoginView's doc comments).
        rememberLocalDesignatedRoot(user)
        storedUserID = user.id.uuidString
        currentUser = user
        // Every path that lands on a currentUser triggers the same
        // background sync — a user who only ever uses email+password login
        // (no working Apple ID sign-in state on this device — see bug-184
        // in buglog.json) would otherwise never sync at all, and never get
        // the default teams.
        triggerBackgroundSync()
    }

    /// Saves/pushes only if User.elevateIfDesignatedRoot() actually changed
    /// something. The club's designated account (Models.swift) has no real Apple
    /// ID and is always created via RegisterView's manual form, so there's no
    /// Apple-verification signal to gate on here — matching on firstName+lastName+
    /// email together (rather than email alone) is what keeps the bar reasonably
    /// high instead.
    private func applyDesignatedRootGrant(_ user: User) {
        let oldRole = user.role
        guard user.elevateIfDesignatedRoot() else { return }
        UserService.save(user, modelContext: modelContext)
        RoleChangeLogService.log(userID: user.id, oldRole: oldRole.rawValue, newRole: user.role.rawValue,
                                  changedBy: "system:designatedRoot", modelContext: modelContext)
    }

    /// Pulls team/event/training/tournament data other users have shared, without
    /// blocking the UI on network/CloudKit latency.
    private func triggerBackgroundSync() {
        Task {
            await SyncOrchestrationService.syncAll(modelContext: modelContext)
            await SyncOrchestrationService.ensureDefaultTeams(modelContext: modelContext)
            // `currentUser` is already set by every call site of
            // triggerBackgroundSync before it's called, and `syncAll` above
            // may have just pulled in new/changed TeamMembership rows for
            // this same user (same ModelContext instance, so the
            // relationship updates in place) — re-subscribing here keeps
            // push notifications in sync with the user's current teams.
            if let currentUser {
                await SyncOrchestrationService.ensureTrainingTournamentSubscriptions(for: currentUser)
            }
            // Refresh the home-screen widget with whatever the sync just
            // pulled in (architecture-review.md §5).
            WidgetRefresher.refresh(modelContext: modelContext, for: currentUser)
        }
        PushNotifications.requestAuthorizationIfNeeded()
    }

    /// Same shared-data pull as `triggerBackgroundSync()`, for the anonymous
    /// landing screen (account-tiers refactor) — but skips the
    /// user-scoped follow-ups that need a real `currentUser`
    /// (training/tournament push subscriptions) and never prompts for push
    /// notification permission before anyone has an account.
    private func triggerAnonymousBackgroundSync() {
        Task {
            await SyncOrchestrationService.syncAll(modelContext: modelContext)
            await SyncOrchestrationService.ensureDefaultTeams(modelContext: modelContext)
            WidgetRefresher.refresh(modelContext: modelContext, for: nil)
        }
    }
}

struct MainTabView: View {
    let currentUser: User
    let onLogout: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    private let networkMonitor = NetworkMonitor.shared

    private var isAdmin: Bool {
        currentUser.role == .admin || currentUser.isRoot
    }

    var body: some View {
        TabView {
            NavigationStack { DashboardView(currentUser: currentUser) }
                .tabItem { Label("Übersicht", systemImage: "house.fill") }

            NavigationStack { EventsListView(currentUser: currentUser) }
                .tabItem { Label("Events", systemImage: "calendar") }

            NavigationStack { TournamentsListView(currentUser: currentUser) }
                .tabItem { Label("Turniere", systemImage: "trophy.fill") }

            NavigationStack { TrainingsListView(currentUser: currentUser) }
                .tabItem { Label("Trainings", systemImage: "figure.run") }

            // On iPad (regular width) an admin/root gets a real sidebar +
            // detail console instead of a pushed list — the admin roster/
            // reporting screens are genuinely desktop-shaped work
            // (architecture-review.md §3.3). Everyone else (iPhone, or a
            // non-admin on any size) keeps the existing pushed-list
            // NavigationStack unchanged.
            Group {
                if horizontalSizeClass == .regular, isAdmin {
                    VereinSplitView(currentUser: currentUser)
                } else {
                    NavigationStack { VereinView(currentUser: currentUser) }
                }
            }
            .tabItem { Label("Verein", systemImage: "building.2.fill") }

            NavigationStack { AccountView(currentUser: currentUser, onLogout: onLogout) }
                .tabItem { Label("Account", systemImage: "person.crop.circle") }
        }
        // One banner for the whole tab bar, not per-screen — see
        // SyncStatusBanner.swift's doc comment.
        .safeAreaInset(edge: .top, spacing: 0) {
            SyncStatusBanner()
        }
        .task {
            NetworkMonitor.shared.start()
            // Keep the home-screen widget current whenever the app is opened,
            // even if no sync runs (architecture-review.md §5).
            WidgetRefresher.refresh(modelContext: modelContext, for: currentUser)
        }
        // When connectivity returns, flush the PendingPush outbox right away
        // instead of waiting for the next full sync (architecture-review.md 2.2).
        .onChange(of: networkMonitor.isOnline) { _, isOnline in
            guard isOnline else { return }
            Task { await SyncOrchestrationService.drainOutbox() }
        }
    }
}

struct LoginView: View {
    let onLogin: (User) -> Void
    let onAppleSignIn: () async -> Void

    // Unfiltered — looked up by email below rather than browsed/tapped, so
    // there's no picker to hide the designated-root account from anymore
    // (that was `visibleUsers`' whole job in the old tap-a-name list —
    // removed along with the list itself, see this struct's history).
    @Query private var users: [User]

    @State private var email = ""
    @State private var password = ""
    @State private var errorMessage: String?
    @State private var showRegister = false
    // Set when the matched account predates password login (passwordHash
    // still empty) — routes to SetPasswordView instead of rejecting.
    @State private var userNeedingPassword: User?

    var body: some View {
        NavigationStack {
            Form {
                Section("Anmelden") {
                    TextField("E-Mail", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Passwort", text: $password)
                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    Button("Anmelden") { attemptLogin() }
                        .disabled(email.trimmingCharacters(in: .whitespaces).isEmpty || password.isEmpty)
                }
                Section {
                    Button("Mit Apple anmelden") { Task { await onAppleSignIn() } }
                }
                Section {
                    Button("Neues Konto erstellen") { showRegister = true }
                }
            }
            .navigationTitle("Anmelden")
            .sheet(isPresented: $showRegister) {
                RegisterView(onRegister: onLogin)
            }
            .sheet(item: $userNeedingPassword) { user in
                SetPasswordView(user: user, onComplete: onLogin)
            }
        }
    }

    private func attemptLogin() {
        errorMessage = nil
        let needle = email.trimmingCharacters(in: .whitespaces).lowercased()
        guard let match = users.first(where: { $0.email.lowercased() == needle }) else {
            errorMessage = "Kein Konto mit dieser E-Mail-Adresse gefunden."
            return
        }
        // Migration path for every pre-password-login account (passwordHash
        // empty). KNOWN LIMITATION: since there's no email verification or
        // backend to check against, anyone who knows/guesses this email can
        // claim the account by being first to set a password for it —
        // accepted trade-off for a small trusted-club app with no server,
        // see PasswordHashing.swift's doc comment.
        guard !match.passwordHash.isEmpty else {
            userNeedingPassword = match
            return
        }
        guard PasswordHashing.verify(password: password, salt: match.passwordSalt, expectedHash: match.passwordHash) else {
            errorMessage = "Falsches Passwort."
            return
        }
        onLogin(match)
    }
}

/// One-time migration step for an account created before password login
/// existed (passwordHash empty) — see LoginView.attemptLogin's doc comment
/// for the trust-model caveat this implies.
struct SetPasswordView: View {
    let user: User
    let onComplete: (User) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var passwordConfirm = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Für \(user.displayName) wurde noch kein Passwort festgelegt. Bitte jetzt eines vergeben.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Passwort festlegen")
                }
                Section {
                    SecureField("Passwort", text: $password)
                    SecureField("Passwort wiederholen", text: $passwordConfirm)
                    if !password.isEmpty, !Validation.passwordMeetsMinimumStrength(password) {
                        Label("Passwort muss mindestens 8 Zeichen haben", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    if !passwordConfirm.isEmpty, password != passwordConfirm {
                        Label("Passwörter stimmen nicht überein", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .navigationTitle("Passwort festlegen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") {
                        let salt = PasswordHashing.makeSalt()
                        user.passwordSalt = salt
                        user.passwordHash = PasswordHashing.hash(password: password, salt: salt)
                        UserService.save(user, modelContext: modelContext)
                        dismiss()
                        onComplete(user)
                    }
                    .disabled(!Validation.passwordMeetsMinimumStrength(password) || password != passwordConfirm)
                }
            }
        }
    }
}

struct RegisterView: View {
    let onRegister: (User) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    // Intentionally unfiltered — only ever read via `users.isEmpty` (the
    // very-first-account bootstrap check below), which needs the full set
    // to answer correctly.
    @Query private var users: [User]

    @State private var email = ""
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var password = ""
    @State private var passwordConfirm = ""
    @State private var isCreating = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Konto") {
                    TextField("Vorname", text: $firstName)
                    TextField("Nachname", text: $lastName)
                    TextField("E-Mail", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if !Validation.isPlausibleEmail(email) {
                        Label("Ungültige E-Mail-Adresse", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                Section("Passwort") {
                    SecureField("Passwort", text: $password)
                    SecureField("Passwort wiederholen", text: $passwordConfirm)
                    if !password.isEmpty, !Validation.passwordMeetsMinimumStrength(password) {
                        Label("Passwort muss mindestens 8 Zeichen haben", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    if !passwordConfirm.isEmpty, password != passwordConfirm {
                        Label("Passwörter stimmen nicht überein", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .navigationTitle("Neues Konto")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Erstellen") {
                        isCreating = true
                        Task {
                            let salt = PasswordHashing.makeSalt()
                            let user = User(email: email, firstName: firstName, lastName: lastName,
                                             passwordHash: PasswordHashing.hash(password: password, salt: salt),
                                             passwordSalt: salt)
                            // The very first account ever created (locally and in CloudKit) becomes
                            // root and admin — otherwise it'd be locked out of the admin features
                            // it needs to set up the club in the first place.
                            if users.isEmpty, !(await SyncOrchestrationService.hasAnyUserIdentity()) {
                                user.isRoot = true
                                user.role = .admin
                            }
                            let oldRole = user.role
                            let becameDesignatedRoot = user.elevateIfDesignatedRoot()
                            modelContext.insert(user)
                            Member.checkMembership(for: user, modelContext: modelContext)
                            UserService.save(user, modelContext: modelContext)
                            if becameDesignatedRoot {
                                RoleChangeLogService.log(userID: user.id, oldRole: oldRole.rawValue, newRole: user.role.rawValue,
                                                          changedBy: "system:designatedRoot", modelContext: modelContext)
                            }
                            dismiss()
                            onRegister(user)
                        }
                    }
                    .disabled(isCreating ||
                              firstName.trimmingCharacters(in: .whitespaces).isEmpty ||
                              lastName.trimmingCharacters(in: .whitespaces).isEmpty ||
                              !Validation.isPlausibleEmail(email) ||
                              !Validation.passwordMeetsMinimumStrength(password) ||
                              password != passwordConfirm)
                }
            }
        }
    }
}
