import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// iPad (regular-width) admin console for the Verein tab — architecture-
/// review.md §3.3: "the admin reporting/roster screens are genuinely
/// desktop-shaped work; VereinHubList's hub → detail maps cleanly onto a
/// NavigationSplitView sidebar." A real persistent sidebar + detail pane
/// instead of `VereinHubList`'s pushed-list `NavigationStack` — same five
/// destinations, same underlying views (`TeamsListView`/`MembersListView`/
/// `PersonenListView`/`UserListView`/`RoleChangeLogView`), only the
/// navigation container differs, so there's no business-logic duplication.
///
/// `MainTabView` picks this over `NavigationStack { VereinView(...) }` only
/// for an admin/root user at `.regular` horizontal size class; a non-admin
/// (who gets plain `TeamsListView`, see `VereinView`) or anyone on iPhone
/// keeps the existing pushed-list navigation untouched.
struct VereinSplitView: View {
    let currentUser: User
    @Environment(\.modelContext) private var modelContext

    enum Destination: String, CaseIterable, Identifiable, Hashable {
        case teams, mitglieder, personen, konten, antraege, rollen, sicherung, willkommen, budget
        var id: String { rawValue }

        var title: String {
            switch self {
            case .teams: return "Teams"
            case .mitglieder: return "Benutzerverwaltung"
            case .personen: return "Personen"
            case .konten: return "App-Konten"
            case .antraege: return "Änderungsanträge"
            case .rollen: return "Rollenänderungen"
            case .sicherung: return "Datensicherung"
            case .willkommen: return "Willkommensbildschirm"
            case .budget: return "Vereinsbudget"
            }
        }

        var systemImage: String {
            switch self {
            case .teams: return "person.3.fill"
            case .mitglieder: return "list.bullet.rectangle"
            case .personen: return "person.crop.rectangle.stack"
            case .konten: return "person.2.badge.key"
            case .antraege: return "person.crop.circle.badge.checkmark"
            case .rollen: return "clock.arrow.circlepath"
            case .sicherung: return "externaldrive.badge.icloud"
            case .willkommen: return "hand.wave"
            case .budget: return "eurosign.bank.building"
            }
        }
    }

    @State private var selection: Destination? = .teams

    var body: some View {
        NavigationSplitView {
            List(Destination.allCases, selection: $selection) { destination in
                Label(destination.title, systemImage: destination.systemImage)
                    .tag(destination)
            }
            .navigationTitle("Verein")
            .refreshable {
                await SyncOrchestrationService.syncAll(modelContext: modelContext)
            }
        } detail: {
            // Each destination gets its own NavigationStack so drilling into
            // a row (e.g. a team, a person) pushes within the detail column
            // instead of replacing the sidebar/detail split.
            NavigationStack {
                detail(for: selection ?? .teams)
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    @ViewBuilder
    private func detail(for destination: Destination) -> some View {
        switch destination {
        case .teams: TeamsListView(currentUser: currentUser)
        case .mitglieder: MembersListView(currentUser: currentUser)
        case .personen: PersonenListView()
        case .konten: UserListView(currentUser: currentUser)
        case .antraege: MemberChangeRequestsView(currentUser: currentUser)
        case .rollen: RoleChangeLogView()
        case .sicherung: FullBackupView()
        case .willkommen: WelcomeScreenSettingsView()
        case .budget: BudgetView(currentUser: currentUser)
        }
    }
}
