import SwiftUI
import SwiftData

/// Chooses the root screen from the Supabase session (`AuthContext`):
/// anonymous → schedule + sign-in, signed in without approval → schedule +
/// Account, approved → full app. Supabase keeps the session in the Keychain.
struct RootView: View {
    @State private var authContext = AuthContext()
    @State private var welcomeMarkdown = ""
    @State private var showWelcome = false
    @State private var syncedUserID: UUID?
    @State private var didAnonymousSync = false

    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Group {
            switch authContext.phase {
            case .loading:
                ProgressView()
            case .signedOut:
                AnonymousLandingView()
            case .signedIn:
                if let user = authContext.currentUser {
                    if authContext.hasFullAccess {
                        MainTabView(currentUser: user, onLogout: logOut)
                    } else {
                        RestrictedTabView(currentUser: user, onLogout: logOut)
                    }
                } else {
                    // Profile not cached yet and the server is unreachable.
                    ContentUnavailableView("Keine Verbindung",
                                           systemImage: "wifi.slash",
                                           description: Text("Dein Konto konnte nicht geladen werden. Bitte versuche es später noch einmal."))
                }
            }
        }
        .environment(authContext)
        .task {
            authContext.start(modelContext: modelContext)
        }
        .onChange(of: authContext.phase) { _, phase in
            switch phase {
            case .signedIn:
                // A later sign-out (also one forced by a block or deletion)
                // syncs schedule-only again, which removes the club data
                // this account could see from the device.
                didAnonymousSync = false
                guard let user = authContext.currentUser, syncedUserID != user.id else { return }
                syncedUserID = user.id
                triggerBackgroundSync()
            case .signedOut:
                syncedUserID = nil
                guard !didAnonymousSync else { return }
                didAnonymousSync = true
                triggerAnonymousBackgroundSync()
            case .loading:
                break
            }
        }
        // Email confirmation and password-reset links.
        .onOpenURL { url in
            Task { await authContext.handleDeepLink(url) }
        }
        .sheet(isPresented: Bindable(authContext).isPasswordRecovery) {
            SetPasswordView(title: "Neues Passwort") {
                authContext.isPasswordRecovery = false
            }
        }
        .alert("Anmeldung", isPresented: Binding(
            get: { authContext.lastError != nil },
            set: { if !$0 { authContext.lastError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(authContext.lastError ?? "")
        }
        .fullScreenCover(isPresented: $showWelcome) {
            WelcomeView(markdown: welcomeMarkdown) { showWelcome = false }
        }
    }

    private func logOut() {
        Task { await authContext.signOut() }
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
            if let currentUser = authContext.currentUser {
                await SyncOrchestrationService.ensureTrainingTournamentSubscriptions(for: currentUser)
            }
            // Refresh the home-screen widget with whatever the sync just
            // pulled in (architecture-review.md §5).
            WidgetRefresher.refresh(modelContext: modelContext, for: authContext.currentUser)
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
