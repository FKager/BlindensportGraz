import SwiftUI
import SwiftData
import Combine
import UniformTypeIdentifiers

struct TrainingDetailView: View {
     @Bindable var training: Training
     let currentUser: User?
     @Environment(\.modelContext) private var modelContext
     @Query private var allTeams: [Team]
     @State private var showMemberList = false
     @State private var showRollCall = false
     @State private var showAddNewMember = false
     // Detail screens open read-only. Only an admin or the root account gets
     // the "Bearbeiten" toolbar toggle that flips this true and unlocks the
     // form (user request 2026-09-08).
     @State private var isEditing = false
     // Eagerly (re)generated below — same "no tap-then-wait, no
     // Button-triggered second sheet" ShareLink convention as every other
     // export in this app (see CalendarEventExport's doc comment for why
     // .ics+ShareLink was chosen over EKEventStore).
     @State private var icsURL: URL?

    var isAdmin: Bool {
        currentUser?.role == .admin
    }

    // Who may leave read-only mode: admins and the club's root account.
    var canEdit: Bool {
        currentUser?.role == .admin || (currentUser?.isRoot ?? false)
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
    // person — now shared with TournamentDetailView and AttendanceRollCallView
    // via SportEvent.rosterAcrossTeams (architecture-review.md §1.2).
    var allMemberships: [TeamMembership] { training.rosterAcrossTeams }

    // Live check against the club's name + Sportart + Zeitpunkt uniqueness
    // rule — this screen edits `training` through bindings with no explicit
    // save step, so a hard block isn't possible here; instead warn inline the
    // moment the edited values collide with another event (see AddTrainingView
    // for the enforced-at-creation path).
    private var collidesWithExistingEvent: Bool {
        SportEvent.duplicate(title: training.title, sport: training.sport,
                             startDate: training.startDate, excluding: training.id,
                             in: modelContext) != nil
    }

    // Members who were marked present — the only rows the read-only
    // Anwesenheit section shows (empty attendance = section hidden entirely).
    private var attendedMemberships: [TeamMembership] {
        allMemberships.filter { attendance(for: $0)?.attended == true }
    }

    // Shown only while editing: the full, always-complete set of editable
    // fields (empty ones included, so they can be filled in).
    @ViewBuilder
    private var editingSections: some View {
        EventImagesSection(images: training.images, currentUser: currentUser, onAdd: addImage, onDelete: deleteImage)

        if collidesWithExistingEvent {
            Section {
                Label("Ein anderer Eintrag hat bereits diesen Titel, diese Sportart und diesen Zeitpunkt. Bitte Titel oder Zeit ändern.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }

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
            Picker("Status", selection: $training.status) {
                Text("Offen").tag(Training.openStatus)
                Text("Durchgeführt").tag(Training.heldStatus)
                Text("Abgesagt").tag(Training.cancelledStatus)
            }
            // Same "no attendance for a cancelled training" rule as the
            // list's swipe action — this is the other place status can
            // change to Abgesagt, so it needs the identical side effect.
            .onChange(of: training.status) {
                if training.status == Training.cancelledStatus {
                    AttendanceService.deleteAll(for: training, modelContext: modelContext)
                }
            }
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
        Section("Anwesenheit") {
            if !allMemberships.isEmpty {
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
                            // Exact-amount fallback for when the desired
                            // value doesn't land on the wheel's €5 steps —
                            // user request 2026-09-14. The wheel below stays
                            // the primary swipe input; this just covers
                            // amounts the wheel can't express, still clamped
                            // to the same 0...90 bound the wheel enforces.
                            TextField("Betrag", value: Binding(
                                get: { Int((attendance(for: membership)?.praeAmount ?? 0).rounded()) },
                                set: { newValue in setPraeAmount(Double(min(90, max(0, newValue))), for: membership) }
                            ), format: .number)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 44)
                                .textFieldStyle(.roundedBorder)
                                .accessibilityLabel("PRAE Betrag genau eingeben")
                            // Swipe-to-select wheel — PRAE is normally paid
                            // in €5 steps from 0 to €90, so this covers the
                            // common case; the TextField above handles
                            // anything off that grid.
                            Picker("PRAE (€)", selection: Binding(
                                get: {
                                    let amount = attendance(for: membership)?.praeAmount ?? 0
                                    let step = (amount / 5).rounded()
                                    return min(90, max(0, Int(step) * 5))
                                },
                                set: { newValue in setPraeAmount(Double(newValue), for: membership) }
                            )) {
                                ForEach(Array(stride(from: 0, through: 90, by: 5)), id: \.self) { value in
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
                if training.totalPraeAmount > 0 {
                    HStack {
                        Text("Gesamtkosten")
                        Spacer()
                        Text("\(Int(training.totalPraeAmount)) €")
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
            TextField("Notizen", text: $training.notes, axis: .vertical)
                .lineLimit(3...6)
        }
    }

    // Default (non-editing) presentation: every empty field is dropped, so
    // only rows that actually carry data are shown (user request 2026-09-08).
    @ViewBuilder
    private var readOnlySections: some View {
        if !training.images.isEmpty {
            EventImagesSection(images: training.images, currentUser: currentUser, onAdd: addImage, onDelete: deleteImage)
                .disabled(true)
        }
        if !training.sport.isEmpty || !training.location.isEmpty {
            Section("Training") {
                if !training.sport.isEmpty {
                    LabeledContent("Sportart", value: training.sport)
                }
                if !training.location.isEmpty {
                    LabeledContent("Veranstaltungsort", value: training.location)
                }
            }
        }
        if !training.fullAddress.isEmpty {
            Section("Adresse") {
                LabeledContent("Adresse", value: training.fullAddress)
            }
        }
        Section("Planung") {
            LabeledContent("Start", value: training.startDate.formatted(date: .long, time: .shortened))
            LabeledContent("Dauer", value: "\(training.durationMinutes) min")
            if !training.focusArea.isEmpty {
                LabeledContent("Schwerpunkt", value: training.focusArea)
            }
            LabeledContent("Status", value: training.statusLabel)
        }
        if !training.teams.isEmpty {
            Section("Beteiligte Teams") {
                ForEach(training.teams) { team in
                    Text(team.name)
                }
            }
        }
        if !attendedMemberships.isEmpty {
            Section("Anwesenheit") {
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
                if training.totalPraeAmount > 0 {
                    HStack {
                        Text("Gesamtkosten")
                        Spacer()
                        Text("\(Int(training.totalPraeAmount)) €")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        if !training.notes.isEmpty {
            Section("Notizen") {
                Text(training.notes)
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
        .navigationTitle(training.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if canEdit {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isEditing ? "Fertig" : "Bearbeiten") {
                        if isEditing {
                            TrainingService.save(training, modelContext: modelContext)
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
        .sheet(isPresented: $showRollCall) {
            AttendanceRollCallView(event: training)
        }
        .sheet(isPresented: $showAddNewMember) {
            AddNewEventMemberView(event: training, praeMax: 90)
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
        AttendanceService.setAttended(attended, for: membership, at: training, modelContext: modelContext)
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
