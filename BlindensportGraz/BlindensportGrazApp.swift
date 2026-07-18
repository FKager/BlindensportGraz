import SwiftUI
import SwiftData

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
            ClubMember.self,
            EventImage.self,
            Attendance.self
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
