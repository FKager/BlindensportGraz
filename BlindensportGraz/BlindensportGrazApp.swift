import SwiftUI
import SwiftData
import os

@main
struct BlindensportGrazApp: App {
    let modelContainer: ModelContainer

    init() {
        let schema = Schema([
            User.self,
            SportEvent.self,
            Tournament.self,
            Training.self,
            Team.self,
            TeamMembership.self,
            EventParticipation.self,
            Member.self,
            EventImage.self,
            Attendance.self,
            TrainingFavorite.self,
            RoleChangeLog.self,
            ExpenseReceipt.self
               ])
        // Local store only. Cross-user, team-scoped sharing is handled by
        // CloudKitSync's manual public-database push/pull, not SwiftData's
        // automatic CloudKit mirroring (which only supports private, per-user sync).
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, cloudKitDatabase: .none)
        do {
            modelContainer = try ModelContainer(for: schema, configurations: [config])
        } catch {
            // The SportEvent/Training/Tournament inheritance refactor is a
            // bigger schema shape change than SwiftData's automatic
            // lightweight migration is documented to support (flattening
            // independent entities into a class hierarchy). Rather than
            // crash outright if an existing local store can't open under the
            // new schema, wipe it and start fresh — CloudKitSync.syncAll()
            // (triggered on next login via RootView) fully repopulates local
            // data from CloudKit's public database, which is already the
            // durable cross-device source of truth. Only truly offline-only,
            // never-synced local edits would be lost, a narrow edge case
            // since every local write already pushes to CloudKit
            // synchronously today.
            //
            // audit.md SwiftData & CloudKit Finding 4: that "only offline-only
            // edits are lost" assumption was never actually verifiable —
            // pushes are fire-and-forget, so nothing recorded whether the
            // local store's last edits had actually reached CloudKit before
            // this reset discards them. A full pending-write ledger is a
            // bigger undertaking than this phase's scope (Phase 10's own
            // Notes); what IS practical here: log exactly what's about to be
            // discarded and why, via the same `os.Logger` category
            // `SyncState`/`CloudKitSync` use, using `SyncState`'s persisted
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
                — wiping and resetting. Last confirmed successful CloudKit sync on this device: \
                \(lastSyncedAt.map { $0.description } ?? "never recorded", privacy: .public). Any local edits made \
                since that point that hadn't yet been confirmed synced will be lost; CloudKit remains the source \
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
                }
        .modelContainer(modelContainer)
           }
       }

// MARK: - Notification Handling for Push Notifications (Toast)
extension BlindensportGrazApp {
   func handleEventCreated(_ notification: Notification) {
       guard let userInfo = notification.userInfo else { return }
       showNotification(
           title: "Neues Event erstellt!",
           body: "Ein neues Sportevent wurde hinzugefügt",
           subtitle: userInfo["eventTitle"] as? String ?? "Sport"
         )
     }

    func handleTournamentCreated(_ notification: Notification) {
       guard let userInfo = notification.userInfo else { return }
       showNotification(
           title: "Neues Turnier erstellt!",
           body: "Ein neues Turnier wurde hinzugefügt",
           subtitle: userInfo["tournamentName"] as? String ?? "Sport"
         )
     }

    func handleTrainingCreated(_ notification: Notification) {
       guard let userInfo = notification.userInfo else { return }
       showNotification(
           title: "Neues Training erstellt!",
           body: "Ein neues Training wurde hinzugefügt",
           subtitle: userInfo["trainingTitle"] as? String ?? "Sport"
         )
     }

    private func showNotification(title: String, body: String, subtitle: String?) {
        // Post notification that can be observed by all views
       NotificationCenter.default.post(
           name: NSNotification.Name("showToast"),
           object: nil,
           userInfo: [
                 "title": title,
                 "body": body,
                 "subtitle": subtitle ?? ""
              ]
         )
     }
}
