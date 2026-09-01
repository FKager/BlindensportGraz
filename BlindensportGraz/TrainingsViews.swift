import SwiftUI
import SwiftData
import Combine
import UniformTypeIdentifiers

struct AddTrainingView: View {
     let currentUser: User?

     @Environment(\.modelContext) private var modelContext
        @Environment(\.dismiss) private var dismiss
      @Query private var allTeams: [Team]
      @Query(sort: \TrainingFavorite.lastUsedAt, order: .reverse) private var favorites: [TrainingFavorite]
      @Query(sort: \Training.startDate, order: .reverse) private var recentTrainings: [Training]

       @State private var title = ""
       @State private var sport = "Torball"
       @State private var location = "Graz"
       @State private var street = ""
       @State private var zip = ""
       @State private var city = ""
       @State private var country = ""
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
        if user.role == .admin { return allTeams }
        let myTeamIDs = Set(user.memberships.map { $0.team.id })
        return allTeams.filter { myTeamIDs.contains($0.id) }
    }

    // Pre-fills name/sport/time/address from a tapped favorite and suggests
    // a start date on the favorite's stored weekday, at its stored
    // time-of-day, in the week following today's — see
    // TrainingFavorite.suggestedStartDate. Also switches includesTime on
    // since a favorite always carries an explicit time.
    private func applyFavorite(_ favorite: TrainingFavorite) {
        title = favorite.title
        sport = favorite.sport
        location = favorite.location
        street = favorite.street
        zip = favorite.zip
        city = favorite.city
        country = favorite.country
        includesTime = true
        startDate = TrainingFavorite.suggestedStartDate(startHour: favorite.startHour, startMinute: favorite.startMinute, weekday: favorite.weekday)
        durationMinutes = favorite.durationMinutes
        // Only pre-checks teams still visible/manageable by this user (the
        // "Beteiligte Teams" list is itself filtered to myTeams) — a team
        // from the favorite that this user can no longer manage is simply
        // not offered, same as if they'd never checked it manually.
        selectedTeamIDs = Set(favorite.teams.map { $0.id })
    }

    private func deleteFavorite(_ favorite: TrainingFavorite) {
        TrainingFavoriteService.delete(favorite, modelContext: modelContext)
    }

    // Rebuilds the Favoriten list from real Training records already in the
    // store — see TrainingFavorite.populateFromRecentTrainings's doc comment.
    // Useful right after this feature shipped (existing trainings predate
    // any auto-recorded favorite) or any time the list should reflect what's
    // actually been trained recently without re-creating trainings by hand.
    private func populateFavoritesFromRecentTrainings() {
        let results = TrainingFavorite.populateFromRecentTrainings(recentTrainings, in: modelContext)
        for (favorite, evictedID) in results {
            TrainingFavoriteService.saveResult(favorite: favorite, evictedID: evictedID, modelContext: modelContext)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                if !favorites.isEmpty || !recentTrainings.isEmpty {
                    Section("Favoriten") {
                        if !favorites.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack {
                                    ForEach(favorites) { favorite in
                                        Button {
                                            applyFavorite(favorite)
                                        } label: {
                                            Text("\(favorite.title) (\(favorite.sport))")
                                        }
                                        .buttonStyle(.bordered)
                                        // Long-press since these are compact chips in a
                                        // horizontal scroll — no room for a swipe gesture
                                        // or a visible per-chip delete button.
                                        .contextMenu {
                                            Button(role: .destructive) {
                                                deleteFavorite(favorite)
                                            } label: {
                                                Label("Löschen", systemImage: "trash")
                                            }
                                        }
                                        // Additive VoiceOver equivalent to the long-press
                                        // contextMenu above — audit.md Accessibility Finding
                                        // 3: this chip had no VoiceOver-reachable way to
                                        // delete a favorite at all (long-press has no direct
                                        // VoiceOver gesture equivalent), same underlying
                                        // deleteFavorite(_:) call either way.
                                        .accessibilityAction(named: "Löschen") {
                                            deleteFavorite(favorite)
                                        }
                                    }
                                }
                            }
                        }
                        if !recentTrainings.isEmpty {
                            Button {
                                populateFavoritesFromRecentTrainings()
                            } label: {
                                Label("Aus letzten Trainings befüllen", systemImage: "arrow.triangle.2.circlepath")
                            }
                        }
                    }
                }
                Section("Training") {
                    TextField("Titel", text: $title)
                    Picker("Sportart", selection: $sport) {
                        ForEach(sports, id: \.self) { s in
                            Label(s, systemImage: SportIcon.symbolName(for: s)).tag(s)
                        }
                       }
                    // Relabeled from "Ort" to "Veranstaltungsort" — see
                    // EventsViews.AddEventView's identical comment.
                    TextField("Veranstaltungsort", text: $location)
                   }
                Section("Adresse") {
                    TextField("Straße", text: $street)
                    TextField("PLZ", text: $zip)
                    TextField("Ort", text: $city)
                    TextField("Land", text: $country)
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
                                            .accessibilityHidden(true)
                                    }
                                }
                            }
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
            .navigationTitle("Neues Training")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") {
                        var teams = myTeams.filter { selectedTeamIDs.contains($0.id) }
                        // Captured before auto-assigned teams are appended
                        // below — favorites store only the manually-checked
                        // selection, see TrainingFavorite.teams' doc comment.
                        let manuallySelectedTeams = teams
                        // Business rule, not a UI convenience: applies to
                        // ANY training of a mapped sport regardless of who
                        // created it or which teams they personally belong
                        // to, so this looks at the full `allTeams` query,
                        // not the role-filtered `myTeams` the checkboxes
                        // above use.
                        if let autoTeamNames = Team.autoAssignTeamNames[sport] {
                            let autoNames = Set(autoTeamNames.map { $0.lowercased() })
                            for team in allTeams where autoNames.contains(team.name.lowercased()) {
                                if !teams.contains(where: { $0.id == team.id }) {
                                    teams.append(team)
                                }
                            }
                        }
                        let training = Training(
                            title: title,
                            sport: sport,
                            location: location,
                            street: street,
                            zip: zip,
                            city: city,
                            country: country,
                            startDate: startDate,
                            durationMinutes: durationMinutes,
                            focusArea: focusArea,
                            notes: notes,
                            createdBy: currentUser?.id.uuidString ?? "",
                            teams: teams
                        )
                        modelContext.insert(training)
                        TrainingService.save(training, modelContext: modelContext)

                        // Auto-add/refresh this name+sport combo in the
                        // shared Favoriten list (max 5, LRU-evicted) — see
                        // TrainingFavorite.recordUsage's doc comment.
                        let (favorite, evictedID) = TrainingFavorite.recordUsage(
                            title: title, sport: sport, startDate: startDate,
                            durationMinutes: durationMinutes,
                            location: location, street: street, zip: zip, city: city, country: country,
                            teams: manuallySelectedTeams, in: modelContext
                        )
                        TrainingFavoriteService.saveResult(favorite: favorite, evictedID: evictedID, modelContext: modelContext)

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
        HStack(alignment: .top, spacing: 12) {
            SportGlyph(sport: training.sport, size: 32)
            VStack(alignment: .leading, spacing: 4) {
                Text(training.title)
                   .font(.headline)
                HStack {
                    Label(training.sport, systemImage: SportIcon.symbolName(for: training.sport))
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
     // Eagerly (re)generated below — same "no tap-then-wait, no
     // Button-triggered second sheet" ShareLink convention as every other
     // export in this app (see CalendarEventExport's doc comment for why
     // .ics+ShareLink was chosen over EKEventStore).
     @State private var icsURL: URL?

    var isAdmin: Bool {
        currentUser?.role == .admin
    }

    // Same admin-bypass as AddTrainingView.myTeams — an admin can reassign a
    // training to any team, not just ones they personally joined.
    var myTeams: [Team] {
        guard let user = currentUser else { return [] }
        if user.role == .admin { return allTeams }
        let myTeamIDs = Set(user.memberships.map { $0.team.id })
        return allTeams.filter { myTeamIDs.contains($0.id) }
    }

    // Every roster entry across all assigned teams, deduped by the underlying
    // person (a user/member could otherwise show twice if they're in two
    // teams both assigned to this training).
    var allMemberships: [TeamMembership] {
        var seenKeys = Set<UUID>()
        var result: [TeamMembership] = []
        for team in training.teams {
            for membership in team.memberships {
                let key = membership.user?.id ?? membership.member?.id ?? membership.id
                if seenKeys.insert(key).inserted {
                    result.append(membership)
                }
            }
        }
        return result.sortedByLastName()
    }

    var body: some View {
        Form {
            EventImagesSection(images: training.images, currentUser: currentUser, onAdd: addImage, onDelete: deleteImage)

            Section("Training") {
                TextField("Titel", text: $training.title)
                TextField("Sportart", text: $training.sport)
                TextField("Veranstaltungsort", text: $training.location)
               }
           Section("Adresse") {
               TextField("Straße", text: $training.street)
               TextField("PLZ", text: $training.zip)
               TextField("Ort", text: $training.city)
               TextField("Land", text: $training.country)
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
                                       .accessibilityHidden(true)
                               }
                           }
                       }
                       .accessibilityAddTraits(training.teams.contains(where: { $0.id == team.id }) ? .isSelected : [])
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
                       // PRAE amount only for helpers/coaches (role "assistant"/
                       // "coach") who were actually present — see Attendance.praeAmount.
                       if membership.role.isHelfer,
                          attendance(for: membership)?.attended == true {
                           HStack {
                               Text("PRAE (€)")
                                   .font(.caption)
                                   .foregroundStyle(.secondary)
                               Spacer()
                               // Swipe-to-select wheel, not free text entry —
                               // PRAE is only ever paid in €10 steps from 0
                               // to €90, so a wheel picker both constrains
                               // input to valid amounts and matches the
                               // "select via swipe" requirement.
                               Picker("PRAE (€)", selection: Binding(
                                   get: {
                                       let amount = attendance(for: membership)?.praeAmount ?? 0
                                       let step = (amount / 10).rounded()
                                       return min(90, max(0, Int(step) * 10))
                                   },
                                   set: { newValue in setPraeAmount(Double(newValue), for: membership) }
                               )) {
                                   ForEach(Array(stride(from: 0, through: 90, by: 10)), id: \.self) { value in
                                       Text("\(value)").tag(value)
                                   }
                               }
                               .labelsHidden()
                               .pickerStyle(.wheel)
                               .frame(width: 100, height: 90)
                               .clipped()
                           }
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
            ToolbarItem(placement: .topBarTrailing) {
                if let icsURL {
                    ShareLink(item: icsURL) {
                        Image(systemName: "calendar.badge.plus")
                    }
                    .accessibilityLabel("Zum Kalender hinzufügen")
                }
            }
        }
        .task(id: CalendarEventExport.fields(for: training)) {
            icsURL = try? CalendarEventExport.icsFile(for: CalendarEventExport.fields(for: training))
        }
        .sheet(isPresented: $showMemberList) {
            // No exportContext (unlike TournamentDetailView) — the
            // TeilnehmerInnenliste export is Sport-Austria tournament
            // paperwork; trainings already have their own equivalent, the
            // Trainingsfrequenzliste (via TrainingsListView's "Berichte"
            // menu), so this view is roster-only for trainings.
            MemberListView(
                itemName: training.title,
                teams: training.teams
            )
        }
        .onDisappear {
            TrainingService.save(training, modelContext: modelContext)
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
        AttendanceService.save(record, modelContext: modelContext)
    }

    private func setPraeAmount(_ amount: Double, for membership: TeamMembership) {
        guard let record = attendance(for: membership) else { return }
        record.praeAmount = amount > 0 ? amount : nil
        AttendanceService.save(record, modelContext: modelContext)
    }

    private func addImage(_ data: Data) {
        let image = EventImage(imageData: data, uploadedBy: currentUser?.id.uuidString ?? "", event: training)
        modelContext.insert(image)
        EventImageService.save(image, modelContext: modelContext)
    }

    private func deleteImage(_ image: EventImage) {
        EventImageService.delete(image, modelContext: modelContext)
    }
}

struct TrainingsListView: View {
     let currentUser: User?
        @Environment(\.modelContext) private var modelContext
        @Query(sort: \Training.startDate, order: .reverse) private var trainings: [Training]
        @State private var showAdd = false
        @State private var showAttendanceTrends = false
        @State private var showTrainingsfrequenzliste = false
        @State private var showPraeCalculation = false
        @State private var showKostZCalculation = false
        @State private var showSammelabrechnung = false
        @State private var showSammelabrechnungSeason = false
        // Same eager-generation + ShareLink convention as MembersListView's
        // import/export (see that view's doc comment) — a hand-rolled
        // "generate on tap" flow previously froze the app under VoiceOver.
        @State private var exportURL: URL?
        @State private var showImporter = false
        @State private var importResultMessage: String?

    var canManageEvents: Bool {
        guard let user = currentUser else { return false }
        return user.role == .admin || user.role == .coach
       }

    // Matches the gating the Trainingsfrequenzliste button used in AccountView
    // before it moved here (see TrainingsfrequenzlisteView's doc comment).
    var isAdmin: Bool {
        currentUser?.role == .admin || (currentUser?.isRoot ?? false)
       }

    var visibleTrainings: [Training] {
        if currentUser?.role == .admin { return trainings }
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
            await SyncOrchestrationService.syncAll(modelContext: modelContext)
        }
        .toolbar {
            // Gated to admin/coach via canManageEvents (Phase 7's AppRole
            // enum, not a raw string) rather than isAdmin — coaches should
            // see their own teams' attendance trends too, unlike the
            // finance-report items below this one which stay admin-only.
            if canManageEvents {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAttendanceTrends = true } label: {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                    }
                    .accessibilityLabel("Anwesenheitstrends")
                }
            }
            if isAdmin {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { showTrainingsfrequenzliste = true } label: {
                            Label("Trainingsfrequenzliste", systemImage: "calendar.badge.checkmark")
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
                        Button { showSammelabrechnungSeason = true } label: {
                            Label("Saison-Sammelabrechnung", systemImage: "doc.zipper.fill")
                        }
                    } label: {
                        Image(systemName: "chart.bar.doc.horizontal")
                    }
                    .accessibilityLabel("Berichte")
                }
            }
            if canManageEvents {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showImporter = true } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                    .accessibilityLabel("Trainings importieren")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if let exportURL {
                        ShareLink(item: exportURL) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel("Trainings exportieren")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Neues Training")
                }
            }
        }
        .sheet(isPresented: $showAdd) {
            AddTrainingView(currentUser: currentUser)
        }
        .sheet(isPresented: $showAttendanceTrends) {
            AttendanceTrendsView()
        }
        .sheet(isPresented: $showTrainingsfrequenzliste) {
            TrainingsfrequenzlisteView()
        }
        .sheet(isPresented: $showPraeCalculation) {
            PraeCalculationView()
        }
        .sheet(isPresented: $showKostZCalculation) {
            KostZCalculationView(currentUser: currentUser)
        }
        .sheet(isPresented: $showSammelabrechnung) {
            SammelabrechnungView()
        }
        .sheet(isPresented: $showSammelabrechnungSeason) {
            SammelabrechnungSeasonView()
        }
        .task(id: trainings.map(\.id)) {
            exportURL = try? TrainingImportExport.exportFile(trainings: trainings)
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
            handleImport(result)
        }
        .alert("Import", isPresented: Binding(
            get: { importResultMessage != nil },
            set: { if !$0 { importResultMessage = nil } }
        )) {
            Button("OK") { importResultMessage = nil }
        } message: {
            Text(importResultMessage ?? "")
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let error):
            importResultMessage = "Import fehlgeschlagen: \(error.localizedDescription)"
        case .success(let url):
            let didAccess = url.startAccessingSecurityScopedResource()
            defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                let outcome = TrainingImportExport.importTrainings(from: data, into: trainings, modelContext: modelContext)
                importResultMessage = outcome.summary
            } catch {
                importResultMessage = "Datei konnte nicht gelesen werden: \(error.localizedDescription)"
            }
        }
    }

    // Routed through TrainingService.delete (phase 14) so the local
    // reminder — see EventReminderService — gets cancelled; still no
    // CloudKit delete push, that scoping is unchanged (no CloudKit delete
    // path exists for Training records, see EventsListView.deleteEvents'
    // identical comment).
    private func deleteTrainings(at offsets: IndexSet) {
        for index in offsets {
            let training = trainings[index]
            modelContext.delete(training)
            TrainingService.delete(training, modelContext: modelContext)
        }
    }
}
