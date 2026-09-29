import SwiftUI
import SwiftData
import Combine

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
   @State private var showRollCall = false
   @State private var showAddNewMember = false
   // Eagerly (re)generated below — same ShareLink convention as every other
   // export in this app; see CalendarEventExport's doc comment for why
   // .ics+ShareLink was chosen over EKEventStore.
   @State private var icsURL: URL?
   // Detail screens open read-only. Only an admin or the root account gets
   // the "Bearbeiten" toolbar toggle that flips this true and unlocks the
   // form (user request 2026-09-08).
   @State private var isEditing = false

   var isAdmin: Bool {
       currentUser?.role == .admin
   }

   // Who may leave read-only mode: admins and the club's root account.
   var canEdit: Bool {
       currentUser?.role == .admin || (currentUser?.isRoot ?? false)
   }

   // Same admin-bypass as AddTournamentView.myTeams — an admin can reassign a
   // tournament to any team, not just ones they personally joined.
   var myTeams: [Team] {
       guard let user = currentUser else { return [] }
       if user.role == .admin { return allTeams }
       let myTeamIDs = Set(user.memberships.map { $0.team.id })
       return allTeams.filter { myTeamIDs.contains($0.id) }
   }

    // Every roster entry across all assigned teams, deduped by the underlying
    // person — shared with TrainingDetailView and AttendanceRollCallView via
    // SportEvent.rosterAcrossTeams (architecture-review.md §1.2).
    var allMemberships: [TeamMembership] { tournament.rosterAcrossTeams }

    var attendedMemberships: [TeamMembership] {
        allMemberships.filter { attendance(for: $0)?.attended == true }
    }

    // Splits the combined roster the old single "Mitgliederliste" used to
    // show into the two roles the Berichte menu's "Teilnehmer Sportler" /
    // "Teilnehmer Helfer" entries each export separately (two Sport-Austria
    // Excel files instead of one mixed one) — mirrors the PRAE-eligibility
    // role check above (role "coach"/"assistant" = Helfer).
    private func isHelfer(_ membership: TeamMembership) -> Bool {
        membership.role.isHelfer
    }

    // "Teilnehmer Sportler" must only include role == .player — NOT simply
    // "!isHelfer" — even now that TeamMembership.role is the closed
    // MembershipRole enum (Phase 7), an unrecognized stored value normalizes
    // to `.other(String)` (see MembershipRole.swift), which `isHelfer` (and
    // this check) both correctly treat as "not player" — but `!isHelfer`
    // would WRONGLY treat it as Sportler. Excel import
    // (TeamImportExport.importMembership) writes whatever string a
    // spreadsheet row has, so a mistyped/unexpected role (e.g. "Trainer"
    // instead of "coach") lands in `.other` — this explicit `== .player`
    // check is what keeps it out of the Sportler roster; `!isHelfer` alone
    // would have let it slip in, which is the original confirmed bug this
    // check exists to prevent (audit.md Architecture Finding 3).
    private func isSportler(_ membership: TeamMembership) -> Bool {
        membership.role == .player
    }

    // Live check against the club's name + Sportart + Zeitpunkt uniqueness
    // rule — this screen edits `tournament` through bindings with no explicit
    // save step, so a hard block isn't possible here; instead warn inline the
    // moment the edited values collide with another event (see
    // AddTournamentView for the enforced-at-creation path).
    private var collidesWithExistingEvent: Bool {
        SportEvent.duplicate(title: tournament.title, sport: tournament.sport,
                             startDate: tournament.startDate, granularity: .day,
                             excluding: tournament.id, in: modelContext) != nil
    }

    // Shown only while editing: the full, always-complete set of editable
    // fields (empty ones included, so they can be filled in).
    @ViewBuilder
    private var editingSections: some View {
        EventImagesSection(images: tournament.images, currentUser: currentUser, onAdd: addImage, onDelete: deleteImage)

        if collidesWithExistingEvent {
            Section {
                Label("Ein anderer Eintrag hat bereits diesen Titel, diese Sportart und diesen Zeitpunkt. Bitte Namen oder Zeit ändern.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }

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
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                    .accessibilityAddTraits(tournament.teams.contains(where: { $0.id == team.id }) ? .isSelected : [])
                }
                Text("Keine Auswahl = für alle sichtbar")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        Section("Teilnehmer:innen") {
            if !allMemberships.isEmpty {
                ForEach(allMemberships) { membership in
                    // PRAE max scales with the tournament's length: PRAE's
                    // €120/day cap (PraeCalculator.dailyCap) times the number
                    // of days it spans (SportEvent.dayCount), since the single
                    // amount entered here is spread evenly across every
                    // deployment day — see PraeCalculator.summary(for:tournament:).
                    AttendanceRow(membership: membership, event: tournament,
                                  maxPrae: Int(PraeCalculator.dailyCap) * tournament.dayCount)
                }
                if tournament.totalPraeAmount > 0 {
                    HStack {
                        Text("Gesamtkosten")
                        Spacer()
                        Text("\(Int(tournament.totalPraeAmount)) €")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Button {
                showAddNewMember = true
            } label: {
                Label("Neues Mitglied hinzufügen", systemImage: "person.badge.plus")
            }
        }
        Section("Notizen") {
            TextField("Notizen", text: $tournament.notes, axis: .vertical)
                .lineLimit(3...6)
        }
    }

    // Localized label for `tournament.status` — mirrors the edit Picker's tags.
    private var statusLabel: String {
        switch tournament.status {
        case "planned": return "Geplant"
        case "ongoing": return "Laufend"
        case "finished": return "Beendet"
        default: return tournament.status
        }
    }

    // Default (non-editing) presentation: every empty field is dropped, so
    // only rows that actually carry data are shown (user request 2026-09-08).
    @ViewBuilder
    private var readOnlySections: some View {
        if !tournament.images.isEmpty {
            EventImagesSection(images: tournament.images, currentUser: currentUser, onAdd: addImage, onDelete: deleteImage)
                .disabled(true)
        }
        if !tournament.sport.isEmpty || !tournament.location.isEmpty {
            Section("Turnier") {
                if !tournament.sport.isEmpty {
                    LabeledContent("Sportart", value: tournament.sport)
                }
                if !tournament.location.isEmpty {
                    LabeledContent("Veranstaltungsort", value: tournament.location)
                }
            }
        }
        if !tournament.fullAddress.isEmpty {
            Section("Adresse") {
                LabeledContent("Adresse", value: tournament.fullAddress)
            }
        }
        Section("Zeitraum") {
            LabeledContent("Start", value: tournament.startDate.formatted(date: .long, time: .omitted))
            LabeledContent("Ende", value: tournament.endDate.formatted(date: .long, time: .omitted))
        }
        Section("Details") {
            LabeledContent("Max. Teams", value: "\(tournament.maxTeams)")
            LabeledContent("Status", value: statusLabel)
        }
        if !tournament.teams.isEmpty {
            Section("Beteiligte Teams") {
                ForEach(tournament.teams) { team in
                    Text(team.name)
                }
            }
        }
        if !attendedMemberships.isEmpty {
            Section("Teilnehmer:innen") {
                ForEach(attendedMemberships) { membership in
                    HStack {
                        Text(membership.displayName)
                        Spacer()
                        if let prae = attendance(for: membership)?.praeAmount, prae > 0 {
                            Text("\(Int(prae)) €")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                if tournament.totalPraeAmount > 0 {
                    HStack {
                        Text("Gesamtkosten")
                        Spacer()
                        Text("\(Int(tournament.totalPraeAmount)) €")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        if !tournament.notes.isEmpty {
            Section("Notizen") {
                Text(tournament.notes)
            }
        }
    }

var body: some View {
    Form {
        if isEditing {
            editingSections
        } else {
            readOnlySections
        }
    }
    .navigationTitle(tournament.title)
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
        if canEdit {
            ToolbarItem(placement: .topBarTrailing) {
                Button(isEditing ? "Fertig" : "Bearbeiten") {
                    if isEditing {
                        TournamentService.save(tournament, modelContext: modelContext)
                    }
                    isEditing.toggle()
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showRollCall = true
                } label: {
                    Label("Anwesenheit", systemImage: "checklist")
                }
            }
        }
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
        ToolbarItem(placement: .topBarTrailing) {
            if let icsURL {
                ShareLink(item: icsURL) {
                    Image(systemName: "calendar.badge.plus")
                }
                .accessibilityLabel("Zum Kalender hinzufügen")
            }
        }
    }
    .task(id: CalendarEventExport.fields(for: tournament)) {
        icsURL = try? CalendarEventExport.icsFile(for: CalendarEventExport.fields(for: tournament))
    }
    .sheet(isPresented: $showAddNewMember) {
        AddNewEventMemberView(event: tournament, praeMax: Int(PraeCalculator.dailyCap) * tournament.dayCount)
    }
    .sheet(isPresented: $showRollCall) {
        AttendanceRollCallView(event: tournament)
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
        KostZTournamentCalculationView(tournament: tournament, currentUser: currentUser)
    }
    .sheet(isPresented: $showPraeCalculation) {
        PraeTournamentCalculationView(tournament: tournament)
    }
    .sheet(isPresented: $showSammelabrechnung) {
        SammelabrechnungTournamentView(tournament: tournament)
    }
    .onDisappear {
        TournamentService.save(tournament, modelContext: modelContext)
    }
   }

    private func attendance(for membership: TeamMembership) -> Attendance? {
        tournament.attendances.first { $0.membership.id == membership.id }
    }

    private func addImage(_ data: Data) {
        let image = EventImage(imageData: data, uploadedBy: currentUser?.id.uuidString ?? "", event: tournament)
        modelContext.insert(image)
        EventImageService.save(image, modelContext: modelContext)
    }

    private func deleteImage(_ image: EventImage) {
        EventImageService.delete(image, modelContext: modelContext)
    }
}
