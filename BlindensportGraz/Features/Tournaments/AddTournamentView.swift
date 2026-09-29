import SwiftUI
import SwiftData
import Combine

struct AddTournamentView: View {
      let currentUser: User?
      @Environment(\.modelContext) private var modelContext
       @Environment(\.dismiss) private var dismiss
       @Query private var allTeams: [Team]

        @State private var title: String
        @State private var sport: String
        @State private var location: String
        @State private var street: String
        @State private var zip: String
        @State private var city: String
        @State private var country: String
        @State private var startDate: Date
        @State private var endDate: Date
        @State private var maxTeams: Int
        @State private var notes: String
        @State private var selectedTeamIDs: Set<UUID> = []
        @State private var showDuplicateAlert = false

        let sports = ["Torball", "Goalball", "Blindenfußball", "Showdown"]

        // `draft` prefills every field from an uploaded invitation (see
        // TournamentInvitationImportView below) — still a completely normal
        // Add form otherwise, nothing here is saved until "Speichern".

        init(currentUser: User?, draft: TournamentDraft? = nil) {
            self.currentUser = currentUser
            let draft = draft ?? TournamentDraft()
            _title = State(initialValue: draft.title)
            _sport = State(initialValue: draft.sport)
            _location = State(initialValue: draft.location)
            _street = State(initialValue: draft.street)
            _zip = State(initialValue: draft.zip)
            _city = State(initialValue: draft.city)
            _country = State(initialValue: draft.country)
            _startDate = State(initialValue: draft.startDate)
            _endDate = State(initialValue: draft.endDate)
            _maxTeams = State(initialValue: draft.maxTeams)
            _notes = State(initialValue: draft.notes)
        }

// Admins manage every team, not just ones they personally joined — a team
    // they just created via AddTeamView has no TeamMembership for them yet, so
    // without this bypass it could never be assigned to anything.
    var myTeams: [Team] {
        guard let user = currentUser else { return [] }
        if user.role == .admin { return allTeams }
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
                                            .foregroundStyle(Theme.Palette.info)
                                            .accessibilityHidden(true)
                                    }
                                }
                            }
                            // Selection state is otherwise conveyed only by the
                            // checkmark icon (hidden from VoiceOver above) —
                            // the .isSelected trait makes the row itself announce
                            // "ausgewählt" instead.
                            .accessibilityAddTraits(selectedTeamIDs.contains(team.id) ? .isSelected : [])
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
                        // Same name + Sportart + Datum as an existing event of
                        // any kind → refuse. Day granularity: the tournament UI
                        // only picks a date, see SportEvent.duplicate.
                        if SportEvent.duplicate(title: title, sport: sport, startDate: startDate, granularity: .day, in: modelContext) != nil {
                            showDuplicateAlert = true
                            return
                        }
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
                        TournamentService.save(tournament, modelContext: modelContext)

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
            .alert("Bereits vorhanden", isPresented: $showDuplicateAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Es gibt bereits eine Veranstaltung mit diesem Titel, dieser Sportart und diesem Zeitpunkt.")
            }
        }
    }
}
