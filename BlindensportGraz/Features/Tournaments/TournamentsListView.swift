import SwiftUI
import SwiftData
import Combine

struct TournamentsListView: View {
     let currentUser: User?
      @Environment(\.modelContext) private var modelContext
       // No query-level `sort:` — `startDate` is inherited from SportEvent and
       // SwiftData traps on an inherited-property sort key path in Release
       // builds (bug-352). `visibleTournaments` sorts (newest first) in memory.
       @Query private var tournaments: [Tournament]
        @State private var showAdd = false
        @State private var showImportInvitation = false

  var canManageEvents: Bool {
      guard let user = currentUser else { return false }
      return user.role == .admin || user.role == .coach
       }

    var visibleTournaments: [Tournament] {
        let sorted = tournaments.sorted { $0.startDate > $1.startDate }
        if currentUser?.role == .admin { return sorted }
        let myTeamIDs = Set(currentUser?.memberships.map { $0.team.id } ?? [])
        return sorted.filter { $0.teams.isEmpty || $0.teams.contains(where: { myTeamIDs.contains($0.id) }) }
    }

   var body: some View {
       List {
          if visibleTournaments.isEmpty {
              ContentUnavailableView("Keine Turniere",
                                    systemImage: "trophy",
                                    description: Text("Lege ein neues Turnier an."))
          } else {
              ForEach(visibleTournaments) { tournament in
                  NavigationLink(value: AppRoute.tournament(tournament)) {
                      TournamentRow(tournament: tournament)
                  }
              }.onDelete(perform: deleteTournaments)
          }
       }
       .navigationTitle("Turniere")
       .refreshable {
           await SyncOrchestrationService.syncAll(modelContext: modelContext)
       }
       .toolbar {
           // Neither PRAE nor KostZ have a "Berichte" menu here anymore —
           // both are per-tournament now (see TournamentDetailView's
           // toolbar), since each needs one specific tournament to scope to.
           if canManageEvents {
               ToolbarItem(placement: .topBarTrailing) {
                   // "Neues Turnier" is by far the more common path, so it
                   // stays a single tap; "aus Einladung" (user request) is
                   // one tap further in, inside the same menu, rather than a
                   // second permanent toolbar icon crowding the bar.
                   Menu {
                       Button { showAdd = true } label: {
                           Label("Neues Turnier", systemImage: "plus")
                       }
                       Button { showImportInvitation = true } label: {
                           Label("Turnier aus Einladung erstellen", systemImage: "doc.text.magnifyingglass")
                       }
                   } label: {
                       Image(systemName: "plus")
                   }
                   .accessibilityLabel("Turnier hinzufügen")
               }
           }
       }
       .sheet(isPresented: $showAdd) {
           AddTournamentView(currentUser: currentUser)
       }
       .sheet(isPresented: $showImportInvitation) {
           TournamentInvitationImportView(currentUser: currentUser)
       }
    }

    // Routed through TournamentService.delete (phase 14) so the local
    // reminder — see EventReminderService — gets cancelled; still no
    // CloudKit delete push, that scoping is unchanged (no CloudKit delete
    // path exists for Tournament records, see EventsListView.deleteEvents'
    // identical comment).
    private func deleteTournaments(at offsets: IndexSet) {
        // Index into the same collection the ForEach renders, not the raw
        // @Query — they no longer share an order (see visibleTournaments).
        let shown = visibleTournaments
        for index in offsets {
            let tournament = shown[index]
            modelContext.delete(tournament)
            TournamentService.delete(tournament, modelContext: modelContext)
        }
    }
}
