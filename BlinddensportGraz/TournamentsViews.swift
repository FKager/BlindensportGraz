import SwiftUI
import SwiftData
import Combine

struct AddTournamentView: View {
      @Environment(\.modelContext) private var modelContext
       @Environment(\.dismiss) private var dismiss

        @State private var name = ""
        @State private var sport = "Torball"
        @State private var venue = "Graz"
        @State private var startDate = Date()
        @State private var endDate = Date().addingTimeInterval(86400)
        @State private var maxTeams = 8
        @State private var notes = ""

     let sports = ["Torball", "Goalball", "Blindenfußball", "Showdown"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Turnier") {
                    TextField("Name", text: $name)
                    Picker("Sportart", selection: $sport) {
                        ForEach(sports, id: \.self) { Text($0) }
                          }
                    TextField("Veranstaltungsort", text: $venue)
                     }
                Section("Zeitraum") {
                    DatePicker("Start", selection: $startDate)
                    DatePicker("Ende", selection: $endDate)
                      }
                Section("Details") {
                    Stepper("Max. Teams: \(maxTeams)", value: $maxTeams, in: 2...64)
                       }
                Section("Notizen") {
                    TextField("Notizen", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("Neues Turnier")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") {
                        let tournament = Tournament(
                            name: name,
                            sport: sport,
                            venue: venue,
                            startDate: startDate,
                            endDate: endDate,
                            maxTeams: maxTeams,
                            notes: notes
                        )
                        modelContext.insert(tournament)
                        try? modelContext.save()

                        // Post notification when tournament is created
                        NotificationCenter.default.post(
                            name: NSNotification.Name("TournamentCreated"),
                            object: nil,
                            userInfo: [
                                "message": "Neues Turnier erstellt!",
                                "title": name,
                                "sport": sport,
                                "venue": venue
                            ]
                        )

                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

struct TournamentRow: View {
   let tournament: Tournament

  var statusColor: Color {
      switch tournament.status {
       case "planned": return .blue
        case "ongoing": return .green
         case "finished": return .gray
          default: return .secondary
           }
     }

  var body: some View {
      VStack(alignment: .leading, spacing: 6) {
          HStack {
              Text(tournament.name)
                .font(.headline)
               Spacer()
             Text(tournament.status)
                 .font(.caption)
                 .padding(.horizontal, 8)
                 .padding(.vertical, 2)
                 .background(statusColor.opacity(0.2))
                 .foregroundColor(statusColor)
          }
          HStack {
              Label(tournament.sport, systemImage: "sportscourt")
               Spacer()
           Label("\(tournament.maxTeams) Teams", systemImage: "person.3.fill")
          }
          .font(.caption)
          .foregroundColor(.secondary)

         HStack {
            Image(systemName: "mappin.and.ellipse")
             Text(tournament.venue)
          }
          .font(.caption)
          .foregroundColor(.secondary)
       }
       .padding(.vertical, 4)
    }
}

struct TournamentDetailView: View {
   @Bindable var tournament: Tournament

var body: some View {
    Form {
        Section("Turnier") {
            TextField("Name", text: $tournament.name)
            TextField("Sportart", text: $tournament.sport)
            TextField("Veranstaltungsort", text: $tournament.venue)
        }
        Section("Zeitraum") {
            DatePicker("Start", selection: $tournament.startDate)
            DatePicker("Ende", selection: $tournament.endDate)
        }
        Section("Details") {
            Stepper("Max. Teams: \(tournament.maxTeams)", value: $tournament.maxTeams, in: 2...64)
             Picker("Status", selection: $tournament.status) {
                 Text("Geplant").tag("planned")
                Text("Laufend").tag("ongoing")
                Text("Beendet").tag("finished")
              }
        }
        Section("Notizen") {
            TextField("Notizen", text: $tournament.notes, axis: .vertical)
                .lineLimit(3...6)
        }
    }
    .navigationTitle(tournament.name)
    .navigationBarTitleDisplayMode(.inline)
   }
}

struct TournamentsListView: View {
     let currentUser: User?
      @Environment(\.modelContext) private var modelContext
       @Query(sort: \Tournament.startDate) private var tournaments: [Tournament]
        @State private var showAdd = false

  var canManageEvents: Bool {
      guard let user = currentUser else { return false }
      return user.role == "admin" || user.role == "coach"
       }

   var body: some View {
       List {
          if tournaments.isEmpty {
              ContentUnavailableView("Keine Turniere",
                                    systemImage: "trophy",
                                    description: Text("Lege ein neues Turnier an."))
          } else {
              ForEach(tournaments) { tournament in
                  NavigationLink {
                      TournamentDetailView(tournament: tournament)
                  } label: {
                      TournamentRow(tournament: tournament)
                  }
              }.onDelete(perform: deleteTournaments)
          }
       }
       .navigationTitle("Turniere")
       .toolbar {
           if canManageEvents {
               ToolbarItem(placement: .topBarTrailing) {
                   Button { showAdd = true } label: {
                       Image(systemName: "plus")
                   }
               }
           }
       }
       .sheet(isPresented: $showAdd) {
           AddTournamentView()
       }
    }

    private func deleteTournaments(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(tournaments[index])
        }
        try? modelContext.save()
    }
}
