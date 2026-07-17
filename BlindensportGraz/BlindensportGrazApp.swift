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
            TrainingAttendance.self,
            TournamentAttendance.self
               ])
        // Local store only. Cross-user, team-scoped sharing is handled by
        // CloudKitSync's manual public-database push/pull, not SwiftData's
        // automatic CloudKit mirroring (which only supports private, per-user sync).
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, cloudKitDatabase: .none)
        do {
            modelContainer = try ModelContainer(for: schema, configurations: [config])
             } catch {
               fatalError("Could not create ModelContainer: \(error)")
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
