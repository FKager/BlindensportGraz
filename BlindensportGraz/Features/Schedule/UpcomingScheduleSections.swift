import SwiftUI
import SwiftData

/// The read-only schedule for visitors and accounts without full access
/// (see `AccessPolicy`): every upcoming training, tournament and event,
/// soonest first, as `List` sections — name, date and location only, no
/// detail screens. Place inside a `List`.
///
/// Same visibility rule as the rest of the app (`NextEventLookup.isVisible`):
/// anonymous visitors only see entries not limited to a team. Cancelled
/// trainings are left out; a multi-day tournament stays listed until its
/// last day.
struct UpcomingScheduleSections: View {
    let viewer: User?

    @Query private var trainings: [Training]
    @Query private var tournaments: [Tournament]
    @Query(filter: #Predicate<SportEvent> { $0.kind == "event" }) private var events: [SportEvent]

    private var today: Date { Calendar.current.startOfDay(for: .now) }

    // In-memory filter + sort: `startDate` is inherited from SportEvent, and
    // SwiftData traps on an inherited-property sort key path in Release
    // builds (bug-352).
    private func upcoming<T: SportEvent>(_ items: [T]) -> [T] {
        items.filter { $0.endDate >= today && NextEventLookup.isVisible(teams: $0.teams, to: viewer) }
            .sorted { $0.startDate < $1.startDate }
    }

    var body: some View {
        let upcomingTrainings = upcoming(trainings).filter { $0.status != Training.cancelledStatus }
        let upcomingTournaments = upcoming(tournaments)
        let upcomingEvents = upcoming(events)

        if upcomingTrainings.isEmpty, upcomingTournaments.isEmpty, upcomingEvents.isEmpty {
            ContentUnavailableView("Noch nichts geplant", systemImage: "calendar",
                                   description: Text("Sobald etwas ansteht, siehst du es hier."))
        }
        if !upcomingTrainings.isEmpty {
            Section("Trainings") {
                ForEach(upcomingTrainings) { ScheduleRow(title: $0.title, start: $0.startDate, end: $0.endDate, location: $0.location) }
            }
        }
        if !upcomingTournaments.isEmpty {
            Section("Turniere") {
                ForEach(upcomingTournaments) { ScheduleRow(title: $0.title, start: $0.startDate, end: $0.endDate, location: $0.location) }
            }
        }
        if !upcomingEvents.isEmpty {
            Section("Events") {
                ForEach(upcomingEvents) { ScheduleRow(title: $0.title, start: $0.startDate, end: $0.endDate, location: $0.location) }
            }
        }
    }
}
