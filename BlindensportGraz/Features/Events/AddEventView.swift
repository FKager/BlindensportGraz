import SwiftUI
import SwiftData

struct AddEventView: View {
    let currentUser: User?
        @Environment(\.modelContext) private var modelContext
        @Environment(\.dismiss) private var dismiss
        @Query(sort: [SortDescriptor(\User.lastName), SortDescriptor(\User.firstName)]) private var allUsers: [User]
        @Query(sort: [SortDescriptor(\Member.lastName), SortDescriptor(\Member.firstName)]) private var allMembers: [Member]

       @State private var title = ""
       @State private var sport = EventsListView.eventTypes[0]
       @State private var location = "Graz"
       @State private var street = ""
       @State private var zip = ""
       @State private var city = ""
       @State private var country = ""
       @State private var startDate = Date()
       @State private var endDate = Date().addingTimeInterval(3600)
       @State private var notes = ""
       // Plain Events aren't Team-scoped (user request 2026-09-12) — people
       // are picked directly instead, via these two id sets.
       @State private var selectedUserIDs: Set<UUID> = []
       @State private var selectedMemberIDs: Set<UUID> = []
       @State private var includesTime = true
       @State private var showDuplicateAlert = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Event") {
                    TextField("Titel", text: $title)
                    Picker("Art der Veranstaltung", selection: $sport) {
                        ForEach(EventsListView.eventTypes, id: \.self) { Text($0) }
                      }
                    // Relabeled from "Ort" to "Veranstaltungsort" (matches
                    // TournamentsViews' existing wording) so it doesn't
                    // collide with the new address section's "Ort" (city)
                    // field below.
                    TextField("Veranstaltungsort", text: $location)
                 }
                Section("Adresse") {
                    TextField("Straße", text: $street)
                    TextField("PLZ", text: $zip)
                    TextField("Ort", text: $city)
                    TextField("Land", text: $country)
                }
                Section("Zeit") {
                    Toggle("Uhrzeit festlegen", isOn: $includesTime)
                    DatePicker("Start", selection: $startDate,
                               displayedComponents: includesTime ? [.date, .hourAndMinute] : [.date])
                    DatePicker("Ende", selection: $endDate,
                               displayedComponents: includesTime ? [.date, .hourAndMinute] : [.date])
                 }
                // Plain Events pick people directly instead of Teams (user
                // request 2026-09-12) — Training/Tournament keep the
                // Team-based flow (AddTrainingView/AddTournamentView).
                if !allUsers.isEmpty || !allMembers.isEmpty {
                    Section("Mitglieder") {
                        if !allUsers.isEmpty {
                            Section("Registrierte Benutzer") {
                                ForEach(allUsers) { user in
                                    MemberSelectionRow(name: user.displayName, isSelected: selectedUserIDs.contains(user.id)) {
                                        if selectedUserIDs.contains(user.id) {
                                            selectedUserIDs.remove(user.id)
                                        } else {
                                            selectedUserIDs.insert(user.id)
                                        }
                                    }
                                }
                            }
                        }
                        if !allMembers.isEmpty {
                            Section("Mitglieder ohne Konto") {
                                ForEach(allMembers) { member in
                                    MemberSelectionRow(name: member.fullName, isSelected: selectedMemberIDs.contains(member.id)) {
                                        if selectedMemberIDs.contains(member.id) {
                                            selectedMemberIDs.remove(member.id)
                                        } else {
                                            selectedMemberIDs.insert(member.id)
                                        }
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
             .navigationTitle("Neues Event")
              .navigationBarTitleDisplayMode(.inline)
              .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                      }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") {
                        // Same name + Sportart + Zeitpunkt as an existing
                        // event of any kind → refuse, see SportEvent.duplicate.
                        if SportEvent.duplicate(title: title, sport: sport, startDate: startDate, in: modelContext) != nil {
                            showDuplicateAlert = true
                            return
                        }
                        let event = SportEvent(
                            title: title,
                            sport: sport,
                            location: location,
                            street: street,
                            zip: zip,
                            city: city,
                            country: country,
                            startDate: startDate,
                            endDate: endDate,
                            notes: notes,
                            createdBy: currentUser?.id.uuidString ?? ""
                            )
                        modelContext.insert(event)
                        SportEventService.save(event, modelContext: modelContext)

                        // Directly-picked people (no Team involved) — see the
                        // "Mitglieder" section above.
                        for user in allUsers where selectedUserIDs.contains(user.id) {
                            let membership = EventMembership(user: user, event: event)
                            modelContext.insert(membership)
                            EventMembershipService.save(membership, modelContext: modelContext)
                        }
                        for member in allMembers where selectedMemberIDs.contains(member.id) {
                            let membership = EventMembership(member: member, event: event)
                            modelContext.insert(membership)
                            EventMembershipService.save(membership, modelContext: modelContext)
                        }
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
