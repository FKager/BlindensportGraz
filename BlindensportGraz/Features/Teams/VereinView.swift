import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Root of the "Verein" tab (see MainTabView) — the merge of the former
/// standalone "Teams" and admin-only "Benutzerverwaltung" tabs. Everyone
/// gets this one tab; only the club-administration parts are gated.
///
/// - Non-admins land straight on the Teams list (its own `.navigationTitle`
///   reads "Teams" — the tab label is still "Verein").
/// - Admins/root get a hub `List` that pushes Teams plus the admin screens
///   (Benutzerverwaltung, Personen, App-Konten, Rollenänderungen) onto the tab's
///   single `NavigationStack`, so none of those wrap themselves anymore.
struct VereinView: View {
    let currentUser: User

    private var isAdmin: Bool {
        currentUser.role == .admin || currentUser.isRoot
    }

    var body: some View {
        if isAdmin {
            VereinHubList(currentUser: currentUser)
        } else {
            TeamsListView(currentUser: currentUser)
        }
    }
}

private struct VereinHubList: View {
    let currentUser: User
    @Environment(\.modelContext) private var modelContext
    @Query private var changeRequests: [MemberChangeRequest]

    private var pendingChangeRequestCount: Int {
        changeRequests.filter { $0.status == MemberChangeRequest.pendingStatus }.count
    }

    var body: some View {
        List {
            Section("Teams") {
                NavigationLink(value: AppRoute.teamsList) {
                    Label("Teams", systemImage: "person.3.fill")
                }
            }

            Section("Verwaltung") {
                NavigationLink(value: AppRoute.membersList) {
                    Label("Benutzerverwaltung", systemImage: "list.bullet.rectangle")
                }
                NavigationLink(value: AppRoute.personenList) {
                    Label("Personen", systemImage: "person.crop.rectangle.stack")
                }
                NavigationLink(value: AppRoute.userList) {
                    Label("App-Konten", systemImage: "person.2.badge.key")
                }
                NavigationLink(value: AppRoute.memberChangeRequests) {
                    HStack {
                        Label("Änderungsanträge", systemImage: "person.crop.circle.badge.checkmark")
                        if pendingChangeRequestCount > 0 {
                            Spacer()
                            CountBadge(count: pendingChangeRequestCount)
                        }
                    }
                }
                NavigationLink(value: AppRoute.roleChangeLog) {
                    Label("Rollenänderungen", systemImage: "clock.arrow.circlepath")
                }
                NavigationLink(value: AppRoute.fullBackup) {
                    Label("Datensicherung", systemImage: "externaldrive.badge.icloud")
                }
                NavigationLink(value: AppRoute.welcomeSettings) {
                    Label("Willkommensbildschirm", systemImage: "hand.wave")
                }
            }

            Section("Finanzen") {
                NavigationLink(value: AppRoute.budget) {
                    Label("Vereinsbudget", systemImage: "eurosign.bank.building")
                }
            }
        }
        .navigationTitle("Verein")
        .refreshable {
            await SyncOrchestrationService.syncAll(modelContext: modelContext)
        }
    }
}
