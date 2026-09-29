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
    @State private var welcomeMarkdown = ""
    @State private var showWelcome = false

    @Environment(\.modelContext) private var modelContext
    // Intentionally unfiltered (audit.md SwiftData & CloudKit Finding 6):
    // resolveAccount() below needs to search every User for an
    // appleUserIdentifier/id match, and check `users.isEmpty` for the
    // very-first-account bootstrap — there's no subset of users that would
    // still answer either question correctly.
    @Query private var users: [User]
    /// The Benutzerverwaltung roster — decides full vs. schedule-only access.
    @Query private var members: [Member]

    private let appleSignIn = AppleSignInCoordinator()

    var body: some View {
        Group {
            if isResolvingAccount {
                ProgressView()
            } else if let user = currentUser {
                if AccessPolicy.hasFullAccess(user, roster: members) {
                    MainTabView(currentUser: user, onLogout: logOut)
                } else {
                    RestrictedTabView(currentUser: user, onLogout: logOut)
                }
            } else {
                AnonymousLandingView(onLogin: onLogin, onAppleSignIn: { await performAppleSignIn() })
            }
        }
        .task {
            await resolveAccount()
        }
        .fullScreenCover(isPresented: $showWelcome) {
            WelcomeView(markdown: welcomeMarkdown) { showWelcome = false }
        }
    }

    /// Clears the same two @AppStorage keys resolveAccount() resumes from —
    /// logout used to leave these set, which is exactly the class of bug
    /// self-delete (AccountView) would otherwise reintroduce (next launch
    /// tries to "resume" an account that's gone / was just logged out of,
    /// per cerebrum's bug-164/bug-373 notes).
    private func logOut() {
        storedAppleUserIdentifier = ""
        storedUserID = ""
        currentUser = nil
    }

    /// If THIS device can see `welcome.md` in its own iCloud Drive (only
    /// true for whichever admin device the file was actually placed on —
    /// see `WelcomeFileWatcher`'s doc comment), pushes its content into the
    /// shared `WelcomeContent` CloudKit record so every other user's device
    /// picks it up on their own next sync. A no-op everywhere else.
    private func syncWelcomeFileIfPresent() {
        guard let localMarkdown = WelcomeFileWatcher.readLocalFile() else { return }
        let content = WelcomeContent.fetchOrCreate(in: modelContext)
        guard content.markdown != localMarkdown else { return }
        content.markdown = localMarkdown
        content.isEnabled = true
        WelcomeContentService.save(content, modelContext: modelContext)
    }

    /// Shows the shared welcome note (already pulled by `syncAll` by the
    /// time this runs — see `triggerBackgroundSync`/
    /// `triggerAnonymousBackgroundSync`) once per app launch, on top of
    /// whichever screen `resolveAccount()` landed on. No-ops if nothing has
    /// been authored yet or an admin has it turned off.
    private func loadWelcomeIfNeeded() {
        guard let content = WelcomeContent.current(in: modelContext), content.isEnabled,
              !content.markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        welcomeMarkdown = content.markdown
        showWelcome = true
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
            syncWelcomeFileIfPresent()
            loadWelcomeIfNeeded()
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
            syncWelcomeFileIfPresent()
            loadWelcomeIfNeeded()
        }
    }
}
