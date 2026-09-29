import SwiftUI
import SwiftData
import AuthenticationServices

struct MainTabView: View {
    let currentUser: User
    let onLogout: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.scenePhase) private var scenePhase
    private let networkMonitor = NetworkMonitor.shared

    // Sharing a file into the app (BlindensportGrazShareExtension +
    // ShareExtensionBridge, "Turnier aus Einladung erstellen" via iOS's
    // share sheet — user request) lands here via .onOpenURL below,
    // regardless of which tab is currently showing.
    @State private var sharedInvitationURL: URL?
    @State private var showSharedInvitationPermissionAlert = false

    private var isAdmin: Bool {
        currentUser.role == .admin || currentUser.isRoot
    }

    // Same gate TournamentsListView's own "Turnier aus Einladung erstellen"
    // button uses (canManageEvents) — sharing a file into the app must not
    // be a way to create a tournament that bypasses that permission check.
    private var canManageEvents: Bool {
        currentUser.role == .admin || currentUser.role == .coach
    }

    var body: some View {
        TabView {
            // Each stack registers the shared AppRoute destinations once, at
            // its root — see AppRoute.swift.
            Tab("Übersicht", systemImage: "house.fill") {
                NavigationStack {
                    DashboardView(currentUser: currentUser)
                        .appRouteDestinations(currentUser: currentUser)
                }
            }

            Tab("Events", systemImage: "calendar") {
                NavigationStack {
                    EventsListView(currentUser: currentUser)
                        .appRouteDestinations(currentUser: currentUser)
                }
            }

            Tab("Turniere", systemImage: "trophy.fill") {
                NavigationStack {
                    TournamentsListView(currentUser: currentUser)
                        .appRouteDestinations(currentUser: currentUser)
                }
            }

            Tab("Trainings", systemImage: "figure.run") {
                NavigationStack {
                    TrainingsListView(currentUser: currentUser)
                        .appRouteDestinations(currentUser: currentUser)
                }
            }

            // On iPad (regular width) an admin/root gets a real sidebar +
            // detail console instead of a pushed list — the admin roster/
            // reporting screens are genuinely desktop-shaped work
            // (architecture-review.md §3.3). Everyone else (iPhone, or a
            // non-admin on any size) keeps the existing pushed-list
            // NavigationStack unchanged.
            Tab("Verein", systemImage: "building.2.fill") {
                if horizontalSizeClass == .regular, isAdmin {
                    VereinSplitView(currentUser: currentUser)
                } else {
                    NavigationStack {
                        VereinView(currentUser: currentUser)
                            .appRouteDestinations(currentUser: currentUser)
                    }
                }
            }

            Tab("Account", systemImage: "person.crop.circle") {
                NavigationStack {
                    AccountView(currentUser: currentUser, onLogout: onLogout)
                        .appRouteDestinations(currentUser: currentUser)
                }
            }
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
        .onOpenURL { url in
            guard let fileURL = ShareExtensionBridge.resolveIncoming(url) else { return }
            presentSharedInvitation(fileURL)
        }
        // The share extension can't always open the app itself, so the
        // shared file also waits in the App Group inbox: pick it up whenever
        // the app becomes active, and after each import closes (in case more
        // than one file was shared).
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active { presentNextPendingInvitation() }
        }
        .onChange(of: sharedInvitationURL) { _, url in
            if url == nil { presentNextPendingInvitation() }
        }
        .fullScreenCover(isPresented: Binding(
            get: { sharedInvitationURL != nil },
            set: { isPresented in
                if !isPresented {
                    if let url = sharedInvitationURL { ShareExtensionBridge.cleanup(url) }
                    sharedInvitationURL = nil
                }
            }
        )) {
            if let sharedInvitationURL {
                TournamentInvitationImportView(currentUser: currentUser, sharedFileURL: sharedInvitationURL)
            }
        }
        .alert("Kein Zugriff", isPresented: $showSharedInvitationPermissionAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Nur Admins und Trainer:innen können auf diese Weise ein Turnier aus einer Einladung erstellen.")
        }
    }

    private func presentNextPendingInvitation() {
        guard sharedInvitationURL == nil, let fileURL = ShareExtensionBridge.nextPendingFile() else { return }
        presentSharedInvitation(fileURL)
    }

    /// Opens the "Turnier aus Einladung erstellen" import for a shared file —
    /// or, for users who may not create tournaments, discards it and says so.
    private func presentSharedInvitation(_ fileURL: URL) {
        guard canManageEvents else {
            ShareExtensionBridge.cleanup(fileURL)
            showSharedInvitationPermissionAlert = true
            return
        }
        sharedInvitationURL = fileURL
    }
}
