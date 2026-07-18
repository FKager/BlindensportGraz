import SwiftUI
import SwiftData
import Combine

struct AddTournamentView: View {
      let currentUser: User?
      @Environment(\.modelContext) private var modelContext
       @Environment(\.dismiss) private var dismiss
       @Query private var allTeams: [Team]

        @State private var title = ""
        @State private var sport = "Torball"
        @State private var location = "Graz"
        @State private var startDate = Date()
        @State private var endDate = Date().addingTimeInterval(86400)
        @State private var maxTeams = 8
        @State private var notes = ""
        @State private var selectedTeamIDs: Set<UUID> = []
        @State private var includesTime = true
                
        let sports = ["Torball", "Goalball", "Blindenfußball", "Showdown"]
        
// Admins manage every team, not just ones they personally joined — a team
    // they just created via AddTeamView has no TeamMembership for them yet, so
    // without this bypass it could never be assigned to anything.
    var myTeams: [Team] {
        guard let user = currentUser else { return [] }
        if user.role == "admin" { return allTeams }
        let myTeamIDs = Set(user.memberships.map { $0.team.id })
        return allTeams.filter { myTeamIDs.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Turnier") {
                    TextField("Name", text: $title)
                    Picker("Sportart", selection: $sport) {
                        ForEach(sports, id: \.self) { Text($0) }
                          }
                    TextField("Veranstaltungsort", text: $location)
                     }
                Section("Zeitraum") {
                    Toggle("Uhrzeit festlegen", isOn: $includesTime)
                    DatePicker("Start", selection: $startDate,
                               displayedComponents: includesTime ? [.date, .hourAndMinute] : [.date])
                    DatePicker("Ende", selection: $endDate,
                               displayedComponents: includesTime ? [.date, .hourAndMinute] : [.date])
                      }
                Section("Details") {
                    Stepper("Max. Teams: \(maxTeams)", value: $maxTeams, in: 2...64)
                       }
                if !myTeams.isEmpty {
                    Section("Beteiligte Teams") {
                        ForEach(myTeams) { team in
                            Button {
                                if selectedTeamIDs.contains(team.id) {
                                    selectedTeamIDs.remove(team.id)
                                } else {
                                    selectedTeamIDs.insert(team.id)
                                }
                            } label: {
                                HStack {
                                    Text(team.name)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    if selectedTeamIDs.contains(team.id) {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.blue)
                                    }
                                }
                            }
                        }
                        Text("Keine Auswahl = für alle sichtbar")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
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
                            title: title,
                            sport: sport,
                            location: location,
                            startDate: startDate,
                            endDate: endDate,
                            maxTeams: maxTeams,
                            notes: notes,
                            createdBy: currentUser?.username ?? "",
                            teams: myTeams.filter { selectedTeamIDs.contains($0.id) }
                        )
                        modelContext.insert(tournament)
                        try? modelContext.save()
                        CloudKitSync.shared.pushTournament(tournament)

                        // Post notification when tournament is created
                        NotificationCenter.default.post(
                            name: NSNotification.Name("TournamentCreated"),
                            object: nil,
                            userInfo: [
                                "message": "Neues Turnier erstellt!",
                                "title": title,
                                "sport": sport,
                                "venue": location
                            ]
                        )

                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
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
              Text(tournament.title)
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
             Text(tournament.location)
          }
          .font(.caption)
          .foregroundColor(.secondary)
       }
       .padding(.vertical, 4)
    }
}

struct TournamentDetailView: View {
   @Bindable var tournament: Tournament
   let currentUser: User?
   @Environment(\.modelContext) private var modelContext
   @Query private var allTeams: [Team]
   @State private var showMemberList = false

   var isAdmin: Bool {
       currentUser?.role == "admin"
   }

   // Same admin-bypass as AddTournamentView.myTeams — an admin can reassign a
   // tournament to any team, not just ones they personally joined.
   var myTeams: [Team] {
       guard let user = currentUser else { return [] }
       if user.role == "admin" { return allTeams }
       let myTeamIDs = Set(user.memberships.map { $0.team.id })
       return allTeams.filter { myTeamIDs.contains($0.id) }
   }

    // Every roster entry across all assigned teams, deduped by the underlying
    // person — mirrors TrainingDetailView.allMemberships.
    var allMemberships: [TeamMembership] {
        var seenKeys = Set<UUID>()
        var result: [TeamMembership] = []
        for team in tournament.teams {
            for membership in team.memberships {
                let key = membership.user?.id ?? membership.clubMember?.id ?? membership.id
                if seenKeys.insert(key).inserted {
                    result.append(membership)
                }
            }
        }
        return result.sorted { $0.displayName < $1.displayName }
    }

    var attendedMemberships: [TeamMembership] {
        allMemberships.filter { attendance(for: $0)?.attended == true }
    }

var body: some View {
    Form {
        EventImagesSection(images: tournament.images, currentUser: currentUser, onAdd: addImage, onDelete: deleteImage)

        Section("Turnier") {
            TextField("Name", text: $tournament.title)
            TextField("Sportart", text: $tournament.sport)
            TextField("Veranstaltungsort", text: $tournament.location)
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
        if !myTeams.isEmpty {
            Section("Beteiligte Teams") {
                ForEach(myTeams) { team in
                    Button {
                        if tournament.teams.contains(where: { $0.id == team.id }) {
                            tournament.teams.removeAll { $0.id == team.id }
                        } else {
                            tournament.teams.append(team)
                        }
                    } label: {
                        HStack {
                            Text(team.name)
                                .foregroundStyle(.primary)
                            Spacer()
                            if tournament.teams.contains(where: { $0.id == team.id }) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                }
                Text("Keine Auswahl = für alle sichtbar")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        if !allMemberships.isEmpty {
            Section("Anwesenheit") {
                ForEach(allMemberships) { membership in
                    Toggle(isOn: Binding(
                        get: { attendance(for: membership)?.attended ?? false },
                        set: { newValue in setAttendance(newValue, for: membership) }
                    )) {
                        Text(membership.displayName)
                    }
                }
            }
        }
        Section("Notizen") {
            TextField("Notizen", text: $tournament.notes, axis: .vertical)
                .lineLimit(3...6)
        }
    }
    .navigationTitle(tournament.title)
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
        if isAdmin {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showMemberList = true
                } label: {
                    Label("Mitgliederliste", systemImage: "list.bullet.clipboard")
                }
            }
        }
    }
    .sheet(isPresented: $showMemberList) {
        MemberListView(
            itemName: tournament.title,
            teams: tournament.teams,
            exportContext: TeilnehmerlisteContext(
                betrifft: tournament.title,
                ort: tournament.location,
                startDate: tournament.startDate,
                endDate: tournament.endDate,
                attendedMemberships: attendedMemberships
            )
        )
    }
    .onDisappear {
        try? modelContext.save()
        CloudKitSync.shared.pushTournament(tournament)
    }
   }

    private func attendance(for membership: TeamMembership) -> Attendance? {
        tournament.attendances.first { $0.membership.id == membership.id }
    }

    private func setAttendance(_ attended: Bool, for membership: TeamMembership) {
        let record: Attendance
        if let existing = attendance(for: membership) {
            existing.attended = attended
            record = existing
        } else {
            record = Attendance(event: tournament, membership: membership, attended: attended)
            modelContext.insert(record)
        }
        try? modelContext.save()
        CloudKitSync.shared.pushAttendance(record)
    }

    private func addImage(_ data: Data) {
        let image = EventImage(imageData: data, uploadedBy: currentUser?.username ?? "", event: tournament)
        modelContext.insert(image)
        try? modelContext.save()
        CloudKitSync.shared.pushEventImage(image)
    }

    private func deleteImage(_ image: EventImage) {
        CloudKitSync.shared.deleteEventImage(image.id)
        modelContext.delete(image)
        try? modelContext.save()
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

    var visibleTournaments: [Tournament] {
        if currentUser?.role == "admin" { return tournaments }
        let myTeamIDs = Set(currentUser?.memberships.map { $0.team.id } ?? [])
        return tournaments.filter { $0.teams.isEmpty || $0.teams.contains(where: { myTeamIDs.contains($0.id) }) }
    }

   var body: some View {
       List {
          if visibleTournaments.isEmpty {
              ContentUnavailableView("Keine Turniere",
                                    systemImage: "trophy",
                                    description: Text("Lege ein neues Turnier an."))
          } else {
              ForEach(visibleTournaments) { tournament in
                  NavigationLink {
                      TournamentDetailView(tournament: tournament, currentUser: currentUser)
                  } label: {
                      TournamentRow(tournament: tournament)
                  }
              }.onDelete(perform: deleteTournaments)
          }
       }
       .navigationTitle("Turniere")
       .refreshable {
           await CloudKitSync.shared.syncAll(modelContext: modelContext)
       }
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
           AddTournamentView(currentUser: currentUser)
       }
    }

    private func deleteTournaments(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(tournaments[index])
        }
        try? modelContext.save()
    }
}
