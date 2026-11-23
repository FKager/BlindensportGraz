import SwiftUI
import SwiftData
import os

@main
struct BlindensportGrazApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    let modelContainer: ModelContainer

    init() {
        LegacyFileCleanup.removeMemberBackups()
        if UITestMode.isActive {
            UIView.setAnimationsEnabled(false)
        }

        // Declared once in ModelSchema.swift — shared with the App Shortcuts
        // intents (and, later, a widget), which open their own read-only
        // container on the same store.
        let schema = AppModelSchema.schema
        let config = AppModelSchema.configuration

        do {
            modelContainer = try ModelContainer(for: schema, configurations: [config])
            // Give the sync layer a container handle for its PendingPush
            // outbox (architecture-review.md 2.2). Done here, before any view
            // exists, so the very first push of the session is already durable.
            SupabaseSync.shared.modelContainer = modelContainer
            UITestMode.insertSampleData(into: modelContainer.mainContext)
        } catch {
            // The SportEvent/Training/Tournament inheritance refactor is a
            // bigger schema shape change than SwiftData's automatic
            // lightweight migration is documented to support (flattening
            // independent entities into a class hierarchy). Rather than
            // crash outright if an existing local store can't open under the
            // new schema, wipe it and start fresh — SupabaseSync.syncAll()
            // (triggered on next login via RootView) fully repopulates local
            // data from Supabase, which is already the
            // durable cross-device source of truth. Only truly offline-only,
            // never-synced local edits would be lost, a narrow edge case
            // since every local write already pushes to Supabase
            // (through the PendingPush outbox).
            //
            // audit.md SwiftData & CloudKit Finding 4: that "only offline-only
            // edits are lost" assumption was never actually verifiable —
            // pushes are fire-and-forget, so nothing recorded whether the
            // local store's last edits had actually reached CloudKit before
            // this reset discards them. A full pending-write ledger is a
            // bigger undertaking than this phase's scope (Phase 10's own
            // Notes); what IS practical here: log exactly what's about to be
            // discarded and why, via the same `os.Logger` category
            // `SyncState`/`SupabaseSync` use, using `SyncState`'s persisted
            // last-known-successful-sync timestamp (survives across
            // launches, read directly from UserDefaults here since
            // `SyncState.shared` isn't safe to depend on this early in
            // launch) as the honest, inspectable trail this finding asks
            // for — an honest "here's my best evidence" replaces the
            // previous silent, unverified assumption.
            let lastSyncedAt = UserDefaults.standard.object(forKey: "SyncState.lastSyncedAt") as? Date
            let resetLogger = Logger(subsystem: "it.a11y.BlindensportGraz", category: "SyncState")
            resetLogger.error("""
                Local store failed to open under the current schema (\(String(describing: error), privacy: .public)) \
                — wiping and resetting. Last confirmed successful sync on this device: \
                \(lastSyncedAt.map { $0.description } ?? "never recorded", privacy: .public). Any local edits made \
                since that point that hadn't yet been confirmed synced will be lost; Supabase remains the source \
                of truth for everything already synced.
                """)
            UserDefaults.standard.set("\(Date.now): \(error)", forKey: "lastModelContainerResetReason")
            BlindensportGrazApp.deleteLocalStore(for: config)
            do {
                modelContainer = try ModelContainer(for: schema, configurations: [config])
            } catch {
                fatalError("Could not create ModelContainer even after resetting the local store: \(error)")
            }
        }
    }

    private static func deleteLocalStore(for config: ModelConfiguration) {
        let fileManager = FileManager.default
        for suffix in ["", "-wal", "-shm"] {
            try? fileManager.removeItem(at: URL(fileURLWithPath: config.url.path + suffix))
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                // UI tests: no animations, so the accessibility audit never
                // measures a screen mid-transition (fading text failed contrast).
                .transaction { if UITestMode.isActive { $0.disablesAnimations = true } }
        }
        .modelContainer(modelContainer)
    }
}
