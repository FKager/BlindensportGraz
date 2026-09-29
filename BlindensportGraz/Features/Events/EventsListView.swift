import SwiftUI
import SwiftData

struct EventsListView: View {
    // Plain-Event-only "Art der Veranstaltung" choices (user request
    // 2026-09-12) — deliberately NOT the Sportart list Training/Tournament
    // use (SportEvent.sport stays free text either way, see Sport.swift's
    // doc comment; this is just a different, event-specific curated list of
    // the same underlying field).
    static let eventTypes = ["Langlaufkurs", "Tandemfahrt", "Generalversammlung", "Weihnachtsfeier", "ÖSTM Nordisch", "ÖM Torball"]

    let currentUser: User?
    @Environment(\.modelContext) private var modelContext
    // SportEvent is polymorphically fetchable (Training/Tournament subclass
    // it), so this needs the `kind` discriminator filter to exclude them —
    // otherwise every training and tournament would also show up as an
    // "Event" here.
    @Query(filter: #Predicate<SportEvent> { $0.kind == "event" }, sort: \SportEvent.startDate)
    private var events: [SportEvent]
    @State private var showAdd = false

    var canManageEvents: Bool {
        guard let user = currentUser else { return false }
        return user.role == .admin || user.role == .coach
    }

    var visibleEvents: [SportEvent] {
        if currentUser?.role == .admin { return events }
        let myTeamIDs = Set(currentUser?.memberships.map { $0.team.id } ?? [])
        return events.filter { $0.teams.isEmpty || $0.teams.contains(where: { myTeamIDs.contains($0.id) }) }
    }

    var body: some View {
        List {
            if visibleEvents.isEmpty {
                ContentUnavailableView("Keine Events",
                                       systemImage: "calendar",
                                       description: Text("Lege ein neues Event an."))
            } else {
                ForEach(visibleEvents) { event in
                    NavigationLink {
                        EventDetailView(event: event, currentUser: currentUser)
                    } label: {
                        EventRow(event: event)
                    }
                }
                .onDelete(perform: deleteEvents)
            }
        }
        .navigationTitle("Events")
        .refreshable {
            await SyncOrchestrationService.syncAll(modelContext: modelContext)
        }
        .toolbar {
            if canManageEvents {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Neues Event")
                }
            }
        }
        .sheet(isPresented: $showAdd) {
            AddEventView(currentUser: currentUser)
        }
    }

    // Plain `try?` here, outside the service layer, is deliberate: CloudKitSync
    // never had a remote delete path for plain SportEvent records (see
    // SportEventService.swift's doc comment) — there is no push/delete call for
    // PersistenceService to gate on, only the local removal itself.
    private func deleteEvents(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(events[index])
        }
        try? modelContext.save()
    }
}
