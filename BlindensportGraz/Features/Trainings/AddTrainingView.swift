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
      // No query-level `sort:` — `startDate` is inherited from SportEvent and
      // SwiftData traps on an inherited-property sort key path in Release
      // builds (bug-352). populateFromRecentTrainings wants newest-first, so
      // sort in memory at the call site.
      @Query private var recentTrainings: [Training]

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
       @State private var showDuplicateAlert = false
       @State private var duplicateAlertMessage = "Es gibt bereits eine Veranstaltung mit diesem Titel, dieser Sportart und diesem Zeitpunkt."
       // Favorite whose weekly-recurring series is being set up (nil = sheet closed).
       @State private var seriesFavorite: TrainingFavorite?
       // Optional weekly-range repeat, entered directly on this screen (not
       // via a TrainingFavorite/TrainingSeriesView) — user request: "specify
       // a range in which for every week a training with the known week day
       // can be created... when only a start date is specified, only one
       // training for this day should be created. the end range is
       // optional." `isRecurring` off (the default) keeps the exact
       // pre-existing single-training save path untouched.
       @State private var isRecurring = false
       @State private var repeatEndDate = Date()
       @State private var showSeriesResultAlert = false
       @State private var seriesResultMessage = ""

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
        let newestFirst = recentTrainings.sorted { $0.startDate > $1.startDate }
        let results = TrainingFavorite.populateFromRecentTrainings(newestFirst, in: modelContext)
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
                                            Button {
                                                seriesFavorite = favorite
                                            } label: {
                                                Label("Serie erstellen…", systemImage: "calendar.badge.plus")
                                            }
                                            Button(role: .destructive) {
                                                deleteFavorite(favorite)
                                            } label: {
                                                Label("Löschen", systemImage: "trash")
                                            }
                                        }
                                        // Additive VoiceOver equivalents to the long-press
                                        // contextMenu above — audit.md Accessibility Finding
                                        // 3: this chip had no VoiceOver-reachable way to
                                        // delete a favorite at all (long-press has no direct
                                        // VoiceOver gesture equivalent), same underlying
                                        // calls either way.
                                        .accessibilityAction(named: "Serie erstellen") {
                                            seriesFavorite = favorite
                                        }
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
                        .onChange(of: startDate) {
                            // Keeps the end date a valid bound for the
                            // DatePicker below (`in: startDate...`) if the
                            // start date moves past it.
                            if repeatEndDate < startDate { repeatEndDate = startDate }
                        }
                    Stepper("Dauer: \(durationMinutes) min", value: $durationMinutes, in: 15...240, step: 15)
                    TextField("Schwerpunkt", text: $focusArea)
                   }
                Section("Wiederholung") {
                    Toggle("Wöchentlich wiederholen", isOn: $isRecurring)
                        .onChange(of: isRecurring) {
                            // Defaults the end date to 8 weeks out the first
                            // time this is switched on, same default the
                            // favorite-based TrainingSeriesView uses.
                            if isRecurring && repeatEndDate <= startDate {
                                repeatEndDate = Calendar.current.date(byAdding: .weekOfYear, value: 8, to: startDate) ?? startDate
                            }
                        }
                    if isRecurring {
                        DatePicker("Enddatum", selection: $repeatEndDate, in: startDate...,
                                   displayedComponents: [.date])
                        Text("Ein Training wird jede Woche am \(startDate.formatted(.dateTime.weekday(.wide))) erstellt, bis einschließlich \(repeatEndDate.formatted(date: .abbreviated, time: .omitted)).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
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

                        if isRecurring {
                            let dates = Training.weeklyRangeDates(from: startDate, through: repeatEndDate)
                            let outcome = TrainingService.createWeeklySeries(
                                title: title, sport: sport, location: location,
                                street: street, zip: zip, city: city, country: country,
                                startDates: dates, durationMinutes: durationMinutes, focusArea: focusArea, notes: notes,
                                createdBy: currentUser?.id.uuidString ?? "", teams: teams, modelContext: modelContext
                            )
                            guard outcome.created > 0 else {
                                duplicateAlertMessage = "Für den gewählten Zeitraum gibt es bereits an jedem Termin ein Training mit diesem Titel und dieser Sportart."
                                showDuplicateAlert = true
                                return
                            }

                            let (favorite, evictedID) = TrainingFavorite.recordUsage(
                                title: title, sport: sport, startDate: startDate,
                                durationMinutes: durationMinutes,
                                location: location, street: street, zip: zip, city: city, country: country,
                                teams: manuallySelectedTeams, in: modelContext
                            )
                            TrainingFavoriteService.saveResult(favorite: favorite, evictedID: evictedID, modelContext: modelContext)

                            var message = "\(outcome.created) Training\(outcome.created == 1 ? "" : "s") erstellt."
                            if outcome.skipped > 0 {
                                message += " \(outcome.skipped) übersprungen (bereits vorhanden)."
                            }
                            seriesResultMessage = message

                            NotificationCenter.default.post(
                                name: NSNotification.Name("TrainingCreated"),
                                object: nil,
                                userInfo: [
                                    "message": "\(outcome.created) neue Trainings erstellt!",
                                    "title": title,
                                    "sport": sport,
                                    "location": location,
                                    "durationMinutes": durationMinutes
                                ]
                            )
                            showSeriesResultAlert = true
                            return
                        }

                        // Same name + Sportart + Zeitpunkt as an existing
                        // event of any kind → refuse, see SportEvent.duplicate.
                        if SportEvent.duplicate(title: title, sport: sport, startDate: startDate, in: modelContext) != nil {
                            duplicateAlertMessage = "Es gibt bereits eine Veranstaltung mit diesem Titel, dieser Sportart und diesem Zeitpunkt."
                            showDuplicateAlert = true
                            return
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
            .alert("Bereits vorhanden", isPresented: $showDuplicateAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(duplicateAlertMessage)
            }
            .alert("Serie erstellt", isPresented: $showSeriesResultAlert) {
                Button("OK") { dismiss() }
            } message: {
                Text(seriesResultMessage)
            }
            .sheet(item: $seriesFavorite) { favorite in
                TrainingSeriesView(favorite: favorite, allTeams: allTeams, currentUser: currentUser)
            }
        }
    }
}
