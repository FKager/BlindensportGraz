import SwiftUI
import SwiftData

struct EventsListView: View {
    let currentUser: User?
    @Environment(\.modelContext) private var modelContext
    // SportEvent is polymorphically fetchable (Training/Tournament subclass
    // it), so this needs the `kind` discriminator filter to exclude them —
    // otherwise every training and tournament would also show up as an
    // "Event" here.
    @Query(filter: #Predicate<SportEvent> { $0.kind == "event" }, sort: \SportEvent.startDate)
    private var events: [SportEvent]
    @State private var showAdd = false

    var canManageEvents: Bool { EventListAccess.canManage(currentUser) }

    var visibleEvents: [SportEvent] { EventListAccess.visible(events, to: currentUser) }

    var body: some View {
        List {
            if visibleEvents.isEmpty {
                EmptyStateView("Keine Events", systemImage: "calendar", description: "Lege ein neues Event an.")
            } else {
                ForEach(visibleEvents) { event in
                    NavigationLink(value: AppRoute.event(event)) {
                        EventRow(event: event)
                    }
                    .deleteDisabled(!canManageEvents)
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

    private func deleteEvents(at offsets: IndexSet) {
        guard canManageEvents else { return }
        for event in EventListAccess.rows(at: offsets, in: visibleEvents) {
            SportEventService.delete(event, modelContext: modelContext)
        }
    }
}
