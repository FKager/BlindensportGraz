import SwiftUI
import SwiftData

struct DashboardView: View {
    let currentUser: User?
    // SportEvent is polymorphically fetchable (Training/Tournament subclass
    // it) — filter to plain events only, same reasoning as EventsListView.
    @Query(filter: #Predicate<SportEvent> { $0.kind == "event" }, sort: \SportEvent.startDate)
    private var events: [SportEvent]
    // No query-level `sort:` — `startDate` is inherited from the SportEvent
    // base class, and SwiftData traps converting an inherited-property key
    // path to an NSSortDescriptor in Release builds (bug-352). Sort in memory.
    @Query private var tournaments: [Tournament]
    @Query private var trainings: [Training]
    @Query private var teams: [Team]

    // The dashboard now applies the SAME team-visibility rule as the
    // Events/Trainings/Tournaments tabs (architecture-review.md §3.2) — a
    // member seeing "5 Trainings" here but only 2 in the tab was confusing.
    private func visible<T>(_ items: [T], teamsOf: (T) -> [Team]) -> [T] {
        items.filter { NextEventLookup.isVisible(teams: teamsOf($0), to: currentUser) }
    }

    var upcomingEvents: [SportEvent] {
        visible(events.filter { $0.endDate >= .now }, teamsOf: { $0.teams })
            .sorted { $0.startDate < $1.startDate }
    }

    var upcomingTrainings: [Training] {
        visible(trainings.filter { $0.startDate >= .now }, teamsOf: { $0.teams })
            .sorted { $0.startDate < $1.startDate }
    }

    var activeTournaments: [Tournament] {
        visible(tournaments.filter { $0.status == "planned" || $0.status == "ongoing" }, teamsOf: { $0.teams })
            .sorted { $0.startDate < $1.startDate }
    }

    var visibleTeams: [Team] {
        guard let currentUser else { return teams }
        if currentUser.role == .admin { return teams }
        let mine = Set(currentUser.memberships.map { $0.team.id })
        return teams.filter { mine.contains($0.id) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection

                nextUpNavigationLink

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    NavigationLink(value: AppRoute.eventsList) {
                        StatCard(icon: "calendar", title: "Events", value: "\(upcomingEvents.count)", color: .blue)
                    }
                    NavigationLink(value: AppRoute.tournamentsList) {
                        StatCard(icon: "trophy.fill", title: "Turniere", value: "\(activeTournaments.count)", color: .yellow)
                    }
                    NavigationLink(value: AppRoute.trainingsList) {
                        StatCard(icon: "figure.run", title: "Trainings", value: "\(upcomingTrainings.count)", color: .green)
                    }
                    NavigationLink(value: AppRoute.teamsList) {
                        StatCard(icon: "person.3.fill", title: "Teams", value: "\(visibleTeams.count)", color: .purple)
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal)

                if !upcomingEvents.isEmpty {
                    sectionHeader("Nächste Events", systemImage: "calendar")
                    ForEach(upcomingEvents.prefix(3)) { event in
                        NavigationLink(value: AppRoute.event(event)) {
                            EventRow(event: event)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal)
                    }
                }

                if !upcomingTrainings.isEmpty {
                    sectionHeader("Kommende Trainings", systemImage: "figure.run")
                    ForEach(upcomingTrainings.prefix(3)) { training in
                        NavigationLink(value: AppRoute.training(training)) {
                            TrainingRow(training: training)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal)
                    }
                }

                if !activeTournaments.isEmpty {
                    sectionHeader("Aktive Turniere", systemImage: "trophy.fill")
                    ForEach(activeTournaments.prefix(3)) { tournament in
                        NavigationLink(value: AppRoute.tournament(tournament)) {
                            TournamentRow(tournament: tournament)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal)
                    }
                }
            }
            .padding(.vertical)
        }
        .navigationTitle("Übersicht")
        .navigationBarTitleDisplayMode(.large)
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Willkommen, \(currentUser?.displayName ?? String(localized: "Sportler"))")
                .font(.title2)
                .bold()
            Text("Hier ist dein Überblick")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
    }

    // "Dein nächster Termin" — the single soonest upcoming training or
    // tournament, as a tappable card. architecture-review.md §3.2.
    @ViewBuilder
    private var nextUpNavigationLink: some View {
        let nextTraining = upcomingTrainings.first
        let nextTournament = activeTournaments.first
        // Whichever starts sooner.
        if nextTraining == nil, nextTournament == nil {
            EmptyView()
        } else if let training = nextTraining,
                  nextTournament == nil || training.startDate <= (nextTournament?.startDate ?? .distantFuture) {
            NavigationLink(value: AppRoute.training(training)) {
                NextUpCard(icon: "figure.run", kind: "Nächstes Training",
                           title: training.title, subtitle: training.startDate.formatted(.dateTime.weekday(.wide).day().month().hour().minute()),
                           tint: .green)
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
        } else if let tournament = nextTournament {
            NavigationLink(value: AppRoute.tournament(tournament)) {
                NextUpCard(icon: "trophy.fill", kind: "Nächstes Turnier",
                           title: tournament.title, subtitle: tournament.startDate.formatted(.dateTime.weekday(.wide).day().month()),
                           tint: .yellow)
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
        }
    }

    private func sectionHeader(_ title: LocalizedStringKey, systemImage: String) -> some View {
        HStack {
            // Purely decorative, paired with the text right next to it —
            // same convention as SportGlyph (audit.md Positive Finding 6) —
            // hidden so VoiceOver doesn't announce the raw SF Symbol name
            // before/after the header text itself.
            Image(systemName: systemImage)
                .accessibilityHidden(true)
            Text(title)
                .font(.headline)
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }
}
