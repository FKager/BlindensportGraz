import SwiftUI
import SwiftData
import Combine

struct AddTrainingView: View {
     let currentUser: User?

     @Environment(\.modelContext) private var modelContext
        @Environment(\.dismiss) private var dismiss
      @Query private var allTeams: [Team]

       @State private var title = ""
       @State private var sport = "Torball"
       @State private var location = "Graz"
       @State private var startDate = Date()
       @State private var durationMinutes = 90
       @State private var focusArea = ""
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
                Section("Training") {
                    TextField("Titel", text: $title)
                    Picker("Sportart", selection: $sport) {
                        ForEach(sports, id: \.self) { Text($0) }
                       }
                    TextField("Ort", text: $location)
                   }
                Section("Planung") {
                    Toggle("Uhrzeit festlegen", isOn: $includesTime)
                    DatePicker("Start", selection: $startDate,
                               displayedComponents: includesTime ? [.date, .hourAndMinute] : [.date])
                    Stepper("Dauer: \(durationMinutes) min", value: $durationMinutes, in: 15...240, step: 15)
                    TextField("Schwerpunkt", text: $focusArea)
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
            .navigationTitle("Neues Training")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") {
                        let training = Training(
                            title: title,
                            sport: sport,
                            location: location,
                            startDate: startDate,
                            durationMinutes: durationMinutes,
                            focusArea: focusArea,
                            notes: notes,
                            createdBy: currentUser?.id.uuidString ?? "",
                            teams: myTeams.filter { selectedTeamIDs.contains($0.id) }
                        )
                        modelContext.insert(training)
                        try? modelContext.save()
                        CloudKitSync.shared.pushTraining(training)

                        // Post notification when training is created
                        NotificationCenter.default.post(
                            name: NSNotification.Name("TrainingCreated"),
                            object: nil,
                            userInfo: [
                                "message": "Neues Training erstellt!",
                                "title": title,
                                "sport": sport,
                                "location": location,
                                "durationMinutes": durationMinutes
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

struct TrainingRow: View {
     let training: Training

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(training.title)
               .font(.headline)
            HStack {
                Label(training.sport, systemImage: "sportscourt")
                Spacer()
                Label("\(training.durationMinutes) min", systemImage: "clock")
               }
               .font(.caption)
               .foregroundColor(.secondary)

            HStack {
                Label(training.location, systemImage: "mappin.and.ellipse")
                Spacer()
                Text(training.startDate, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute())
               }
               .font(.caption)
               .foregroundColor(.secondary)
        }
       .padding(.vertical, 4)
    }
}

struct TrainingDetailView: View {
     @Bindable var training: Training
     let currentUser: User?
     @Environment(\.modelContext) private var modelContext
     @Query private var allTeams: [Team]
     @State private var showMemberList = false

    var isAdmin: Bool {
        currentUser?.role == "admin"
    }

    // Same admin-bypass as AddTrainingView.myTeams — an admin can reassign a
    // training to any team, not just ones they personally joined.
    var myTeams: [Team] {
        guard let user = currentUser else { return [] }
        if user.role == "admin" { return allTeams }
        let myTeamIDs = Set(user.memberships.map { $0.team.id })
        return allTeams.filter { myTeamIDs.contains($0.id) }
    }

    // Every roster entry across all assigned teams, deduped by the underlying
    // person (a user/clubMember could otherwise show twice if they're in two
    // teams both assigned to this training).
    var allMemberships: [TeamMembership] {
        var seenKeys = Set<UUID>()
        var result: [TeamMembership] = []
        for team in training.teams {
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
            EventImagesSection(images: training.images, currentUser: currentUser, onAdd: addImage, onDelete: deleteImage)

            Section("Training") {
                TextField("Titel", text: $training.title)
                TextField("Sportart", text: $training.sport)
                TextField("Ort", text: $training.location)
               }
           Section("Planung") {
               DatePicker("Start", selection: $training.startDate)
                   .onChange(of: training.startDate) { training.recomputeEndDate() }
               Stepper("Dauer: \(training.durationMinutes) min", value: $training.durationMinutes, in: 15...240, step: 15)
                   .onChange(of: training.durationMinutes) { training.recomputeEndDate() }
               TextField("Schwerpunkt", text: $training.focusArea)
              }
           if !myTeams.isEmpty {
               Section("Beteiligte Teams") {
                   ForEach(myTeams) { team in
                       Button {
                           if training.teams.contains(where: { $0.id == team.id }) {
                               training.teams.removeAll { $0.id == team.id }
                           } else {
                               training.teams.append(team)
                           }
                       } label: {
                           HStack {
                               Text(team.name)
                                   .foregroundStyle(.primary)
                               Spacer()
                               if training.teams.contains(where: { $0.id == team.id }) {
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
                TextField("Notizen", text: $training.notes, axis: .vertical)
                    .lineLimit(3...6)
              }
         }
        .navigationTitle(training.title)
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
                itemName: training.title,
                teams: training.teams,
                exportContext: TeilnehmerlisteContext(
                    betrifft: training.title,
                    ort: training.location,
                    startDate: training.startDate,
                    endDate: training.endDate,
                    attendedMemberships: attendedMemberships
                )
            )
        }
        .onDisappear {
            try? modelContext.save()
            CloudKitSync.shared.pushTraining(training)
        }
    }

    private func attendance(for membership: TeamMembership) -> Attendance? {
        training.attendances.first { $0.membership.id == membership.id }
    }

    private func setAttendance(_ attended: Bool, for membership: TeamMembership) {
        let record: Attendance
        if let existing = attendance(for: membership) {
            existing.attended = attended
            record = existing
        } else {
            record = Attendance(event: training, membership: membership, attended: attended)
            modelContext.insert(record)
        }
        try? modelContext.save()
        CloudKitSync.shared.pushAttendance(record)
    }

    private func addImage(_ data: Data) {
        let image = EventImage(imageData: data, uploadedBy: currentUser?.id.uuidString ?? "", event: training)
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

struct TrainingsListView: View {
     let currentUser: User?
        @Environment(\.modelContext) private var modelContext
        @Query(sort: \Training.startDate) private var trainings: [Training]
        @State private var showAdd = false

    var canManageEvents: Bool {
        guard let user = currentUser else { return false }
        return user.role == "admin" || user.role == "coach"
       }

    var visibleTrainings: [Training] {
        if currentUser?.role == "admin" { return trainings }
        let myTeamIDs = Set(currentUser?.memberships.map { $0.team.id } ?? [])
        return trainings.filter { $0.teams.isEmpty || $0.teams.contains(where: { myTeamIDs.contains($0.id) }) }
    }

    var body: some View {
        List {
           if visibleTrainings.isEmpty {
               ContentUnavailableView("Keine Trainings",
                                      systemImage: "figure.run",
                                      description: Text("Lege ein neues Training an."))
              } else {
                  ForEach(visibleTrainings) { training in
                    NavigationLink {
                        TrainingDetailView(training: training, currentUser: currentUser)
                          } label: {
                           TrainingRow(training: training)
                         }
                       }.onDelete(perform: deleteTrainings)
                      }
                 }
        .navigationTitle("Trainings")
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
            AddTrainingView(currentUser: currentUser)
        }
    }

    private func deleteTrainings(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(trainings[index])
        }
        try? modelContext.save()
    }
}
