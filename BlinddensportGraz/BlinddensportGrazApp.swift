import SwiftUI
import SwiftData

@main
struct BlinddensportGrazApp: App {
    let modelContainer: ModelContainer

    init() {
        let schema = Schema([
            User.self,
            SportEvent.self,
            Tournament.self,
            Training.self,
            Team.self,
            TeamMembership.self,
            EventParticipation.self
               ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
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
           }
       }
}

// MARK: - Notification Handling for Push Notifications (Toast)
extension BlinddensportGrazApp {
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
