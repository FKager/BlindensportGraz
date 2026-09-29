import SwiftData
import SwiftUI

/// Root screen for the "anonymous" account tier (account-tiers refactor) —
/// shown by `RootView` in place of the old full-screen `LoginView` whenever
/// `currentUser == nil`. Deliberately NOT the full `MainTabView` tab bar:
/// a not-logged-in visitor only gets the read-only upcoming schedule (name,
/// date and location of every upcoming training, tournament and event —
/// `UpcomingScheduleSections`, shared with `RestrictedTabView`) plus
/// "Registrieren"/"Anmelden" — everything else requires an account that's
/// listed in the Benutzerverwaltung (see `AccessPolicy`).
struct AnonymousLandingView: View {
    let onLogin: (User) -> Void
    let onAppleSignIn: () async -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var showLogin = false
    @State private var showRegister = false

    var body: some View {
        NavigationStack {
            List {
                // Sign-up/sign-in first: below a long schedule the buttons
                // would be hard to reach, especially with VoiceOver.
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

                    Button(action: register) {
                        Text("Registrieren")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.Fill.info)
                    .listRowBackground(Color.clear)

                    Button(action: logIn) {
                        Text("Anmelden")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .listRowBackground(Color.clear)
                }
                .listRowSeparator(.hidden)

                UpcomingScheduleSections(viewer: nil)
            }
            .navigationTitle("Termine")
            .navigationBarTitleDisplayMode(.inline)
            .refreshable {
                await SyncOrchestrationService.syncAll(modelContext: modelContext)
            }
            .sheet(isPresented: $showRegister) {
                RegisterView(onRegister: onLogin)
            }
            .sheet(isPresented: $showLogin) {
                LoginView(onLogin: onLogin, onAppleSignIn: onAppleSignIn)
            }
        }
    }

    private func register() {
        showRegister = true
    }

    private func logIn() {
        showLogin = true
    }
}
