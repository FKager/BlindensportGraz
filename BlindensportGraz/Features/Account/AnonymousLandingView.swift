import SwiftData
import SwiftUI

/// Root screen for visitors without an account, shown by `RootView` when no
/// one is signed in: only Übersicht, the read-only upcoming schedule
/// (`UpcomingScheduleSections`, shared with `RestrictedTabView`), and Account
/// with "Registrieren" and "Anmelden". Everything else needs an account listed
/// in the Benutzerverwaltung (see `AccessPolicy`).
struct AnonymousLandingView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var showLogin = false
    @State private var showRegister = false

    var body: some View {
        TabView {
            Tab("Übersicht", systemImage: "house.fill") {
                NavigationStack {
                    List {
                        UpcomingScheduleSections(viewer: nil)
                    }
                    .navigationTitle("Übersicht")
                    .refreshable {
                        await SyncOrchestrationService.syncAll(modelContext: modelContext)
                    }
                }
            }

            Tab("Account", systemImage: "person.crop.circle") {
                NavigationStack {
                    account
                        .navigationTitle("Account")
                }
            }
        }
        .sheet(isPresented: $showRegister) {
            RegisterView()
        }
        .sheet(isPresented: $showLogin) {
            LoginView()
        }
    }

    private var account: some View {
        List {
            Section {
                VStack(spacing: Theme.Spacing.s) {
                    HeroIcon(systemName: "figure.run.circle.fill")
                    Text("Blindensport Graz")
                        .font(.title2)
                        .bold()
                        .accessibilityAddTraits(.isHeader)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.s)
                .listRowBackground(Color.clear)

                Button { showRegister = true } label: {
                    Text("Registrieren")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.Fill.info)
                .listRowBackground(Color.clear)

                Button { showLogin = true } label: {
                    Text("Anmelden")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .listRowBackground(Color.clear)
            }
            .listRowSeparator(.hidden)
        }
    }
}
