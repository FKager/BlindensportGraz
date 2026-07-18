import SwiftUI
import SwiftData

struct AddEventView: View {
    let currentUser: User?
        @Environment(\.modelContext) private var modelContext
        @Environment(\.dismiss) private var dismiss
        @Query private var allTeams: [Team]

       @State private var title = ""
       @State private var sport = "Torball"
       @State private var location = "Graz"
       @State private var startDate = Date()
       @State private var endDate = Date().addingTimeInterval(3600)
       @State private var notes = ""
       @State private var selectedTeamIDs: Set<UUID> = []
       @State private var includesTime = true

    let sports = ["Torball", "Goalball", "Blindenfußball", "Showdown", "Judo", "Leichtathletik", "Schwimmen", "Ski", "Radfahren"]

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
                Section("Event") {
                    TextField("Titel", text: $title)
                    Picker("Sportart", selection: $sport) {
                        ForEach(sports, id: \.self) { Text($0) }
                      }
                    TextField("Ort", text: $location)
                 }
                Section("Zeit") {
                    Toggle("Uhrzeit festlegen", isOn: $includesTime)
                    DatePicker("Start", selection: $startDate,
                               displayedComponents: includesTime ? [.date, .hourAndMinute] : [.date])
                    DatePicker("Ende", selection: $endDate,
                               displayedComponents: includesTime ? [.date, .hourAndMinute] : [.date])
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
             .navigationTitle("Neues Event")
              .navigationBarTitleDisplayMode(.inline)
              .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                      }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") {
                        let event = SportEvent(
                            title: title,
                            sport: sport,
                            location: location,
                            startDate: startDate,
                            endDate: endDate,
                            notes: notes,
                            createdBy: currentUser?.username ?? "",
                            teams: myTeams.filter { selectedTeamIDs.contains($0.id) }
                            )
                        modelContext.insert(event)
                        try? modelContext.save()
                        CloudKitSync.shared.pushEvent(event)
                       dismiss()
                     }
                      .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                   }
                }
           }
        }
    }

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

    var canManageEvents: Bool {
        guard let user = currentUser else { return false }
        return user.role == "admin" || user.role == "coach"
    }

    var visibleEvents: [SportEvent] {
        if currentUser?.role == "admin" { return events }
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
            await CloudKitSync.shared.syncAll(modelContext: modelContext)
        }
        .toolbar {
            if canManageEvents {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                }
            }
        }
        .sheet(isPresented: $showAdd) {
            AddEventView(currentUser: currentUser)
        }
    }

    private func deleteEvents(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(events[index])
        }
        try? modelContext.save()
    }
}

struct EventRow: View {
    let event: SportEvent

    var body: some View {
        HStack(spacing: 12) {
            VStack {
                Text(event.startDate, format: .dateTime.day())
                      .font(.title2)
                      .bold()
                Text(event.startDate, format: .dateTime.month(.abbreviated))
                      .font(.caption)
                      .foregroundStyle(.secondary)
              }
              .frame(width: 50)
              .padding(.vertical, 4)
              .background(.blue.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                      .font(.headline)
                Text(event.sport)
                      .font(.subheadline)
                      .foregroundStyle(.secondary)
                Label(event.location, systemImage: "mappin.and.ellipse")
                      .font(.caption)
                      .foregroundStyle(.secondary)
              }
          }
          .padding(.vertical, 4)
      }
}

struct EventDetailView: View {
      @Bindable var event: SportEvent
    let currentUser: User?
      @Environment(\.modelContext) private var modelContext
      @Query private var users: [User]
      @Query private var allTeams: [Team]
      @State private var showMemberList = false

    var isAdmin: Bool {
        currentUser?.role == "admin"
    }

    // Same admin-bypass as AddEventView.myTeams — an admin can reassign an
    // event to any team, not just ones they personally joined.
    var myTeams: [Team] {
        guard let user = currentUser else { return [] }
        if user.role == "admin" { return allTeams }
        let myTeamIDs = Set(user.memberships.map { $0.team.id })
        return allTeams.filter { myTeamIDs.contains($0.id) }
    }

    var body: some View {
        Form {
            EventImagesSection(images: event.images, currentUser: currentUser, onAdd: addImage, onDelete: deleteImage)

            Section("Details") {
                LabeledContent("Sportart", value: event.sport)
                LabeledContent("Ort", value: event.location)
                LabeledContent("Start", value: event.startDate.formatted(date: .long, time: .shortened))
                LabeledContent("Ende", value: event.endDate.formatted(date: .long, time: .shortened))
              }

            if !event.notes.isEmpty {
                Section("Notizen") {
                    Text(event.notes)
                 }
             }

            if !myTeams.isEmpty {
                Section("Beteiligte Teams") {
                    ForEach(myTeams) { team in
                        Button {
                            if event.teams.contains(where: { $0.id == team.id }) {
                                event.teams.removeAll { $0.id == team.id }
                            } else {
                                event.teams.append(team)
                            }
                        } label: {
                            HStack {
                                Text(team.name)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if event.teams.contains(where: { $0.id == team.id }) {
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

            Section("Teilnehmer (\(event.participations.count))") {
                if event.participations.isEmpty {
                    Text("Noch keine Teilnehmer")
                          .foregroundColor(.secondary)
                  } else {
                     ForEach(event.participations) { p in
                        HStack {
                            Text(p.user.displayName)
                            Spacer()
                            Text(p.status)
                                  .font(.caption)
                                  .foregroundColor(.secondary)
                           }
                      }

                       if let user = currentUser,
                           !event.participations.contains(where: { $0.user.id == user.id }) {
                        Button("Selbst anmelden") {
                            let participation = EventParticipation(user: user, event: event, status: "confirmed")
                            modelContext.insert(participation)
                            try? modelContext.save()
                            CloudKitSync.shared.pushParticipation(participation)
                           }
                       }
                  }
             }
        }
        .navigationTitle(event.title)
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
            MemberListView(itemName: event.title, teams: event.teams)
        }
        .onDisappear {
            try? modelContext.save()
            CloudKitSync.shared.pushEvent(event)
        }
    }

    private func addImage(_ data: Data) {
        let image = EventImage(imageData: data, uploadedBy: currentUser?.username ?? "", event: event)
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
