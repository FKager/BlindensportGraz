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
        @State private var street = ""
        @State private var zip = ""
        @State private var city = ""
        @State private var country = ""
        @State private var startDate = Date()
        @State private var endDate = Date().addingTimeInterval(86400)
        @State private var maxTeams = 8
        @State private var notes = ""
        @State private var selectedTeamIDs: Set<UUID> = []

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
                        ForEach(sports, id: \.self) { s in
                            Label(s, systemImage: SportIcon.symbolName(for: s)).tag(s)
                        }
                          }
                    TextField("Veranstaltungsort", text: $location)
                     }
                Section("Adresse") {
                    TextField("Straße", text: $street)
                    TextField("PLZ", text: $zip)
                    TextField("Ort", text: $city)
                    TextField("Land", text: $country)
                }
                Section("Zeitraum") {
                    DatePicker("Start", selection: $startDate, displayedComponents: [.date])
                    DatePicker("Ende", selection: $endDate, displayedComponents: [.date])
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
                        if let autoTeamNames = Team.autoAssignTeamNames[sport] {
                            Text("Bei \(sport) werden \(autoTeamNames.joined(separator: ", ")) automatisch zugewiesen.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
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
                        var teams = myTeams.filter { selectedTeamIDs.contains($0.id) }
                        // Same business rule as AddTrainingView: applies to
                        // ANY tournament of a mapped sport regardless of who
                        // created it, so this looks at the full `allTeams`
                        // query, not the role-filtered `myTeams` the
                        // checkboxes above use.
                        if let autoTeamNames = Team.autoAssignTeamNames[sport] {
                            let autoNames = Set(autoTeamNames.map { $0.lowercased() })
                            for team in allTeams where autoNames.contains(team.name.lowercased()) {
                                if !teams.contains(where: { $0.id == team.id }) {
                                    teams.append(team)
                                }
                            }
                        }
                        let tournament = Tournament(
                            title: title,
                            sport: sport,
                            location: location,
                            street: street,
                            zip: zip,
                            city: city,
                            country: country,
                            startDate: startDate,
                            endDate: endDate,
                            maxTeams: maxTeams,
                            notes: notes,
                            createdBy: currentUser?.id.uuidString ?? "",
                            teams: teams
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
    HStack(alignment: .top, spacing: 12) {
      SportGlyph(sport: tournament.sport, size: 32)
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
              Label(tournament.sport, systemImage: SportIcon.symbolName(for: tournament.sport))
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
      }
       .padding(.vertical, 4)
    }
}

struct TournamentDetailView: View {
   @Bindable var tournament: Tournament
   let currentUser: User?
   @Environment(\.modelContext) private var modelContext
   @Query private var allTeams: [Team]
   @State private var showTeilnehmerSportler = false
   @State private var showTeilnehmerHelfer = false
   @State private var showKostZCalculation = false
   @State private var showPraeCalculation = false
   @State private var showSammelabrechnung = false

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
                let key = membership.user?.id ?? membership.member?.id ?? membership.id
                if seenKeys.insert(key).inserted {
                    result.append(membership)
                }
            }
        }
        return result.sortedByLastName()
    }

    var attendedMemberships: [TeamMembership] {
        allMemberships.filter { attendance(for: $0)?.attended == true }
    }

    // Splits the combined roster the old single "Mitgliederliste" used to
    // show into the two roles the Berichte menu's "Teilnehmer Sportler" /
    // "Teilnehmer Helfer" entries each export separately (two Sport-Austria
    // Excel files instead of one mixed one) — mirrors the PRAE-eligibility
    // role check above (role "coach"/"assistant" = Helfer).
    private func isHelfer(_ membership: TeamMembership) -> Bool {
        ["coach", "assistant"].contains(membership.role)
    }

    // "Teilnehmer Sportler" must only include role == "player" — NOT simply
    // "!isHelfer" — because TeamMembership.role isn't a closed enum: Excel
    // import (TeamImportExport.importMembership) writes whatever string a
    // spreadsheet row has, so a mistyped/unexpected role (e.g. "Trainer"
    // instead of "coach") would slip into the Sportler roster under the old
    // `!isHelfer` check since it isn't literally "coach"/"assistant" either.
    private func isSportler(_ membership: TeamMembership) -> Bool {
        membership.role == "player"
    }

var body: some View {
    Form {
        EventImagesSection(images: tournament.images, currentUser: currentUser, onAdd: addImage, onDelete: deleteImage)

        Section("Turnier") {
            TextField("Name", text: $tournament.title)
            TextField("Sportart", text: $tournament.sport)
            TextField("Veranstaltungsort", text: $tournament.location)
        }
        Section("Adresse") {
            TextField("Straße", text: $tournament.street)
            TextField("PLZ", text: $tournament.zip)
            TextField("Ort", text: $tournament.city)
            TextField("Land", text: $tournament.country)
        }
        Section("Zeitraum") {
            DatePicker("Start", selection: $tournament.startDate, displayedComponents: [.date])
            DatePicker("Ende", selection: $tournament.endDate, displayedComponents: [.date])
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
            Section("Teilnehmer:innen") {
                ForEach(allMemberships) { membership in
                    Toggle(isOn: Binding(
                        get: { attendance(for: membership)?.attended ?? false },
                        set: { newValue in setAttendance(newValue, for: membership) }
                    )) {
                        Text(membership.displayName)
                    }
                    // PRAE amount only for helpers/coaches (role "assistant"/
                    // "coach") who were actually present — see Attendance.praeAmount.
                    if ["coach", "assistant"].contains(membership.role),
                       attendance(for: membership)?.attended == true {
                        HStack {
                            Text("PRAE (€)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            TextField("0", value: Binding(
                                get: { attendance(for: membership)?.praeAmount ?? 0 },
                                set: { newValue in setPraeAmount(newValue, for: membership) }
                            ), format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        }
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
            // Per-tournament PRAE + KostZ. Both used to live on
            // TournamentsListView's list-level "Berichte" menu; moved here
            // since each is scoped to one specific tournament's own PRAE
            // entries (PraeTournamentCalculationView/
            // KostZTournamentCalculationView), which the list view can't
            // supply — TrainingsListView's "Berichte" menu is unaffected and
            // stays month-wide/list-level, since Trainings' PRAE/KostZ are
            // still summed across a whole month, not per-event.
            // "Teilnehmer Sportler"/"Teilnehmer Helfer" (formerly one combined
            // "Mitgliederliste" toolbar button) live here too now, split by
            // role so each gets its own Sport-Austria Excel export.
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { showTeilnehmerSportler = true } label: {
                        Label("Teilnehmer Sportler", systemImage: "figure.run")
                    }
                    Button { showTeilnehmerHelfer = true } label: {
                        Label("Teilnehmer Helfer", systemImage: "hand.raised.fill")
                    }
                    Button { showPraeCalculation = true } label: {
                        Label("PRAE-Berechnung", systemImage: "eurosign.circle.fill")
                    }
                    Button { showKostZCalculation = true } label: {
                        Label("KostZ-Berechnung", systemImage: "doc.text.fill")
                    }
                    Button { showSammelabrechnung = true } label: {
                        Label("Sammelabrechnung", systemImage: "doc.zipper")
                    }
                } label: {
                    Image(systemName: "chart.bar.doc.horizontal")
                }
                .accessibilityLabel("Berichte")
            }
        }
    }
    .sheet(isPresented: $showTeilnehmerSportler) {
        MemberListView(
            itemName: tournament.title,
            teams: tournament.teams,
            exportContext: TeilnehmerlisteContext(
                betrifft: tournament.title,
                ort: tournament.locationWithCountry,
                startDate: tournament.startDate,
                endDate: tournament.endDate,
                attendedMemberships: attendedMemberships.filter(isSportler),
                fileNamePrefix: "TN-Sportler"
            ),
            membershipFilter: { isSportler($0) && attendance(for: $0)?.attended == true },
            kindLabel: "Teilnehmer Sportler"
        )
    }
    .sheet(isPresented: $showTeilnehmerHelfer) {
        MemberListView(
            itemName: tournament.title,
            teams: tournament.teams,
            exportContext: TeilnehmerlisteContext(
                betrifft: tournament.title,
                ort: tournament.locationWithCountry,
                startDate: tournament.startDate,
                endDate: tournament.endDate,
                attendedMemberships: attendedMemberships.filter(isHelfer),
                fileNamePrefix: "TN-Helfer"
            ),
            membershipFilter: { isHelfer($0) && attendance(for: $0)?.attended == true },
            kindLabel: "Teilnehmer Helfer"
        )
    }
    .sheet(isPresented: $showKostZCalculation) {
        KostZTournamentCalculationView(tournament: tournament)
    }
    .sheet(isPresented: $showPraeCalculation) {
        PraeTournamentCalculationView(tournament: tournament)
    }
    .sheet(isPresented: $showSammelabrechnung) {
        SammelabrechnungTournamentView(tournament: tournament)
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

    private func setPraeAmount(_ amount: Double, for membership: TeamMembership) {
        guard let record = attendance(for: membership) else { return }
        record.praeAmount = amount > 0 ? amount : nil
        try? modelContext.save()
        CloudKitSync.shared.pushAttendance(record)
    }

    private func addImage(_ data: Data) {
        let image = EventImage(imageData: data, uploadedBy: currentUser?.id.uuidString ?? "", event: tournament)
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
       @Query(sort: \Tournament.startDate, order: .reverse) private var tournaments: [Tournament]
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
           // Neither PRAE nor KostZ have a "Berichte" menu here anymore —
           // both are per-tournament now (see TournamentDetailView's
           // toolbar), since each needs one specific tournament to scope to.
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
