import SwiftData
import SwiftUI

/// Root screen for the "anonymous" account tier (account-tiers refactor) —
/// shown by `RootView` in place of the old full-screen `LoginView` whenever
/// `currentUser == nil`. Deliberately NOT the full `MainTabView` tab bar:
/// per the product decision behind this refactor, a not-logged-in visitor
/// only gets a read-only teaser (the next upcoming Training/Tournament/
/// Event) plus "Registrieren"/"Anmelden" calls to action — full
/// browsing/RSVP/admin features all require logging in.
struct AnonymousLandingView: View {
    /// Icon column in the preview rows; grows with Dynamic Type.
    @ScaledMetric(relativeTo: .title3) private var previewIconWidth = 28.0

    let onLogin: (User) -> Void
    let onAppleSignIn: () async -> Void

    @Query private var trainings: [Training]
    @Query private var tournaments: [Tournament]
    @Query(filter: #Predicate<SportEvent> { $0.kind == "event" }) private var events: [SportEvent]

    @State private var showLogin = false
    @State private var showRegister = false

    // Live @Query-backed equivalents of NextEventLookup.nextTraining/
    // nextTournament/nextEvent (those do one-shot FetchDescriptor fetches
    // for the App-Intents/widget context, which has no @Environment — not
    // reactive, so not a fit for a SwiftUI screen that needs to update once
    // RootView's triggerAnonymousBackgroundSync() finishes pulling data in
    // the background). Reuses NextEventLookup.isVisible for the exact same
    // "unscoped items only, for a nil/logged-out viewer" visibility rule
    // every other list in the app already applies.
    private var nextTraining: Training? {
        trainings.filter { $0.startDate >= .now && NextEventLookup.isVisible(teams: $0.teams, to: nil) }
            .min { $0.startDate < $1.startDate }
    }
    private var nextTournament: Tournament? {
        tournaments.filter { $0.startDate >= .now && NextEventLookup.isVisible(teams: $0.teams, to: nil) }
            .min { $0.startDate < $1.startDate }
    }
    private var nextEvent: SportEvent? {
        events.filter { $0.startDate >= .now && NextEventLookup.isVisible(teams: $0.teams, to: nil) }
            .min { $0.startDate < $1.startDate }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.xxl) {
                    VStack(spacing: Theme.Spacing.s) {
                        HeroIcon(systemName: "figure.run.circle.fill")
                        Text("Blindensport Graz")
                            .font(.title2)
                            .bold()
                    }
                    .padding(.top, Theme.Spacing.hero)

                    VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                        Text("Demnächst")
                            .font(.headline)
                        if nextTraining == nil, nextTournament == nil, nextEvent == nil {
                            ContentUnavailableView("Noch nichts geplant",
                                                    systemImage: "calendar",
                                                    description: Text("Sobald etwas ansteht, siehst du es hier."))
                        } else {
                            if let nextTraining {
                                previewRow(kind: "Training", systemImage: "figure.run",
                                           title: nextTraining.title, date: nextTraining.startDate,
                                           location: nextTraining.location)
                            }
                            if let nextTournament {
                                previewRow(kind: "Turnier", systemImage: "trophy.fill",
                                           title: nextTournament.title, date: nextTournament.startDate,
                                           location: nextTournament.location)
                            }
                            if let nextEvent {
                                previewRow(kind: "Event", systemImage: "calendar",
                                           title: nextEvent.title, date: nextEvent.startDate,
                                           location: nextEvent.location)
                            }
                        }
                    }
                    .padding(.horizontal)

                    VStack(spacing: Theme.Spacing.m) {
                        Button {
                            showRegister = true
                        } label: {
                            Text("Registrieren")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)

                        Button {
                            showLogin = true
                        } label: {
                            Text("Anmelden")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.horizontal)
                    .padding(.top, Theme.Spacing.s)

                    Spacer(minLength: 24)
                }
            }
            .sheet(isPresented: $showRegister) {
                RegisterView(onRegister: onLogin)
            }
            .sheet(isPresented: $showLogin) {
                LoginView(onLogin: onLogin, onAppleSignIn: onAppleSignIn)
            }
        }
    }

    @ViewBuilder
    private func previewRow(kind: String, systemImage: String, title: String, date: Date, location: String) -> some View {
        HStack(spacing: Theme.Spacing.m) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(Theme.Palette.info)
                .frame(width: previewIconWidth)
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(title).font(.subheadline).bold()
                Text("\(kind) · \(date.formatted(date: .abbreviated, time: .shortened))\(location.isEmpty ? "" : " · \(location)")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
    }
}
