import SwiftUI
import SwiftData

struct DashboardView: View {
    let currentUser: User?
    @Query(sort: \SportEvent.startDate) private var events: [SportEvent]
    @Query(sort: \Tournament.startDate) private var tournaments: [Tournament]
    @Query(sort: \Training.startDate) private var trainings: [Training]
    @Query private var teams: [Team]

    var upcomingEvents: [SportEvent] {
        events.filter { $0.endDate >= .now }
    }

    var upcomingTrainings: [Training] {
        trainings.filter { $0.startDate >= .now }
    }

    var activeTournaments: [Tournament] {
        tournaments.filter { $0.status == "planned" || $0.status == "ongoing" }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    StatCard(icon: "calendar", title: "Events", value: "\(upcomingEvents.count)", color: .blue)
                    StatCard(icon: "trophy.fill", title: "Turniere", value: "\(activeTournaments.count)", color: .yellow)
                    StatCard(icon: "figure.run", title: "Trainings", value: "\(upcomingTrainings.count)", color: .green)
                    StatCard(icon: "person.3.fill", title: "Teams", value: "\(teams.count)", color: .purple)
                }
                .padding(.horizontal)

                if !upcomingEvents.isEmpty {
                    sectionHeader("Nächste Events", systemImage: "calendar")
                    ForEach(upcomingEvents.prefix(3)) { event in
                        EventRow(event: event)
                            .padding(.horizontal)
                    }
                }

                if !upcomingTrainings.isEmpty {
                    sectionHeader("Kommende Trainings", systemImage: "figure.run")
                    ForEach(upcomingTrainings.prefix(3)) { training in
                        TrainingRow(training: training)
                            .padding(.horizontal)
                    }
                }

                if !activeTournaments.isEmpty {
                    sectionHeader("Aktive Turniere", systemImage: "trophy.fill")
                    ForEach(activeTournaments.prefix(3)) { tournament in
                        TournamentRow(tournament: tournament)
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
            Text("Willkommen, \(currentUser?.displayName ?? "Sportler")")
                .font(.title2)
                .bold()
            Text("Hier ist dein Überblick")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
    }

    private func sectionHeader(_ title: String, systemImage: String) -> some View {
        HStack {
            Image(systemName: systemImage)
            Text(title)
                .font(.headline)
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }
}

struct StatCard: View {
    let icon: String
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
            Text(value)
                .font(.title)
                .bold()
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }
}
