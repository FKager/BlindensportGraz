import SwiftUI
import SwiftData

/// Signed-in accounts without full access (not listed in the
/// Benutzerverwaltung — see `AccessPolicy`): only the upcoming schedule
/// (name, date, location) plus their own Account tab, which they need for
/// logging out and "Mitgliedschaft beantragen". Once an admin adds them to
/// the Benutzerverwaltung and it syncs, `RootView` switches to the full app.
struct RestrictedTabView: View {
    let currentUser: User
    let onLogout: () -> Void

    @Environment(\.modelContext) private var modelContext

    var body: some View {
        TabView {
            Tab("Termine", systemImage: "calendar") {
                NavigationStack {
                    List {
                        UpcomingScheduleSections(viewer: currentUser)
                    }
                    .navigationTitle("Termine")
                    .refreshable {
                        await SyncOrchestrationService.syncAll(modelContext: modelContext)
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
        .safeAreaInset(edge: .top, spacing: 0) {
            SyncStatusBanner()
        }
        .task {
            NetworkMonitor.shared.start()
        }
    }
}
