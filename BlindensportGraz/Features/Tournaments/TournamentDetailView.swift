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
   @State private var icsFile: Result<URL, any Error>?
   // Detail screens open read-only. Only an admin or the root account gets
   // the "Bearbeiten" toolbar toggle that flips this true and unlocks the
   // form (user request 2026-09-08).
   @State private var isEditing = false

   var isAdmin: Bool {
       (currentUser?.can(.clubManage) ?? false)
   }

   // Who may leave read-only mode: admins and the club's root account.
   var canEdit: Bool {
       (currentUser?.can(.clubManage) ?? false)
   }

   // Same admin-bypass as AddTournamentView.myTeams — an admin can reassign a
   // tournament to any team, not just ones they personally joined.
   var myTeams: [Team] {
       guard let user = currentUser else { return [] }
       if user.can(.clubManage) { return allTeams }
       let myTeamIDs = Set(user.memberships.map { $0.team.id })
       return allTeams.filter { myTeamIDs.contains($0.id) }
   }

    // Every roster entry across all assigned teams, deduped by the underlying
    // person — shared with TrainingDetailView and AttendanceRollCallView via
    // SportEvent.rosterAcrossTeams (architecture-review.md §1.2).
    var allMemberships: [TeamMembership] { tournament.rosterAcrossTeams }

    /// The same people as the Teilnehmerlisten and the Sammelabrechnung.
    var attendedMemberships: [TeamMembership] {
        TeilnehmerlisteExporter.attendedMemberships(of: tournament)
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
                    .foregroundStyle(Theme.Palette.warning)
            }
        }

        TournamentFieldsSections(tournament: tournament)
        EventTeamsPicker(event: tournament, teams: myTeams)
        Section(heading: "Teilnehmer:innen") {
            if !allMemberships.isEmpty {
                ForEach(allMemberships) { membership in
                    // PRAE max scales with the tournament's length: PRAE's
                    // €120/day cap (PraeCalculator.dailyCap) times the number
                    // of days it spans (SportEvent.dayCount), since the single
                    // amount entered here is spread evenly across every
                    // deployment day — see PraeCalculator.summaries(for:tournament:).
                    AttendanceRow(membership: membership, event: tournament,
                                  maxPrae: Int(PraeCalculator.dailyCap) * tournament.dayCount)
                }
                PraeTotalRow(amount: tournament.totalPraeAmount)
            }
            Button {
                showAddNewMember = true
            } label: {
                Label("Neues Mitglied hinzufügen", systemImage: "person.badge.plus")
            }
        }
        Section(heading: "Notizen") {
            StackedField(label: "Notizen", text: $tournament.notes, axis: .vertical)
                .lineLimit(3...6)
        }
        TournamentDocumentsSection(tournament: tournament, currentUser: currentUser)
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
            Section(heading: "Turnier") {
                if tournament.typeName != EventType.Behavior.tournament.defaultTypeName {
                    LabeledContent("Art der Veranstaltung", value: tournament.typeName)
                }
                if !tournament.sport.isEmpty {
                    LabeledContent("Sportart", value: tournament.sport)
                }
                if !tournament.location.isEmpty {
                    LabeledContent("Veranstaltungsort", value: tournament.location)
                }
            }
        }
        if !tournament.fullAddress.isEmpty {
            Section(heading: "Adresse") {
                LabeledContent("Adresse", value: tournament.fullAddress)
            }
        }
        Section(heading: "Zeitraum") {
            LabeledContent("Start", value: tournament.startDate.formatted(date: .long, time: .omitted))
            LabeledContent("Ende", value: tournament.endDate.formatted(date: .long, time: .omitted))
        }
        Section(heading: "Details") {
            LabeledContent("Max. Teams", value: "\(tournament.maxTeams)")
            LabeledContent("Status", value: tournament.statusLabel)
        }
        if !tournament.teams.isEmpty {
            Section(heading: "Beteiligte Teams") {
                ForEach(tournament.teams) { team in
                    Text(team.name)
                }
            }
        }
        if !attendedMemberships.isEmpty {
            Section(heading: "Teilnehmer:innen") {
                ForEach(attendedMemberships) { membership in
                    HStack {
                        Text(membership.displayName)
                        Spacer()
                        if let prae = attendance(for: membership)?.praeAmount, prae > 0 {
                            Text("\(Int(prae)) €")
                                .foregroundStyle(Theme.Palette.secondary)
                        }
                    }
                }
                PraeTotalRow(amount: tournament.totalPraeAmount)
            }
        }
        if !tournament.notes.isEmpty {
            Section(heading: "Notizen") {
                Text(tournament.notes)
            }
        }
        TournamentDocumentsSection(tournament: tournament, currentUser: currentUser)
    }

var body: some View {
    Form {
        if isEditing {
            editingSections
            FormActionButtons(primaryTitle: "Fertig", cancelTitle: nil, onPrimary: finishEditing)
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
                    if isEditing { finishEditing() } else { isEditing = true }
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
            ExportShareButton(file: icsFile, label: "Zum Kalender hinzufügen", systemImage: "calendar.badge.plus")
        }
    }
    .task(id: CalendarEventExport.fields(for: tournament)) {
        icsFile = ExportShareButton.prepare("Tournament calendar entry") {
            try CalendarEventExport.icsFile(for: CalendarEventExport.fields(for: tournament))
        }
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
                ort: tournament.cityWithCountry,
                startDate: tournament.startDate,
                endDate: tournament.endDate,
                attendedMemberships: TeilnehmerlisteExporter.sportler(of: tournament),
                fileNamePrefix: "TN-Sportler"
            ),
            kindLabel: "Teilnehmer Sportler"
        )
    }
    .sheet(isPresented: $showTeilnehmerHelfer) {
        MemberListView(
            itemName: tournament.title,
            teams: tournament.teams,
            exportContext: TeilnehmerlisteContext(
                betrifft: tournament.title,
                ort: tournament.cityWithCountry,
                startDate: tournament.startDate,
                endDate: tournament.endDate,
                attendedMemberships: TeilnehmerlisteExporter.helfer(of: tournament),
                fileNamePrefix: "TN-Helfer"
            ),
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
        SammelabrechnungTournamentView(tournament: tournament, currentUser: currentUser)
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

    /// Saves and leaves edit mode — the "Fertig" button in the bar and the
    /// large one at the end of the form.
    private func finishEditing() {
        TournamentService.save(tournament, modelContext: modelContext)
        isEditing = false
    }
}
