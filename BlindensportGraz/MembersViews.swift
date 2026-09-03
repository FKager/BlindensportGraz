import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// The club's member roster ("Mitglieder"), pushed from `VereinView`'s
/// admin hub (see MainTabView) — this used to be its own admin-only
/// "Benutzerverwaltung" tab, self-wrapping a NavigationStack + "Fertig"
/// button because it doubled as a sheet. New app accounts are auto-flagged
/// as club members by matching against this roster (see
/// Member.checkMembership in Models.swift). `Member.memberOfGVSC` makes
/// club membership an explicit per-entry flag rather than something implied
/// by mere presence on the roster, since this list also carries
/// helpers/coaches who aren't necessarily formal members. Account/role
/// administration (`UserListView`) and the role-change audit log
/// (`RoleChangeLogView`) are now siblings under the same hub rather than
/// toolbar buttons here.
struct MembersListView: View {
    let currentUser: User
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\Member.lastName), SortDescriptor(\Member.firstName)])
    private var members: [Member]
    @Query private var users: [User]
    @State private var showAdd = false
    // Two-step delete: swipe fills this, the confirmationDialog commits it.
    @State private var pendingDeletion: [Member] = []
    // Eagerly (re)generated whenever the roster changes, mirroring the
    // ShareLink pattern established for TeilnehmerlisteExport (see
    // MemberListView/cerebrum.md) — this user relies on VoiceOver, and a
    // hand-rolled "generate on tap, then show a share sheet" flow is the
    // specific pattern that previously froze the app under VoiceOver.
    // ShareLink itself, pointed at an already-ready file, is the safe path.
    @State private var exportURL: URL?
    @State private var showImporter = false
    @State private var importResultMessage: String?
    // Roster edits are one of audit.md's two explicitly-prioritized areas
    // for visible save/sync failure signaling (alongside role changes, see
    // UserListView) — see ServiceFailureSignal.swift.
    private let failureSignal = ServiceFailureSignal.shared

    // Extracted from `body` so the modifier chain on `List` stays short
    // enough for the type-checker (it timed out with these inline).
    private var deletionDialogShown: Binding<Bool> {
        Binding(get: { !pendingDeletion.isEmpty }, set: { if !$0 { pendingDeletion = [] } })
    }
    private var importAlertShown: Binding<Bool> {
        Binding(get: { importResultMessage != nil }, set: { if !$0 { importResultMessage = nil } })
    }
    private var failureAlertShown: Binding<Bool> {
        Binding(get: { failureSignal.message != nil }, set: { if !$0 { failureSignal.clear() } })
    }

    var body: some View {
        List {
            if members.isEmpty {
                ContentUnavailableView("Keine Mitglieder",
                                       systemImage: "building.columns",
                                       description: Text("Lege ein neues Mitglied an."))
            } else {
                ForEach(members) { member in
                    NavigationLink {
                        MemberDetailView(member: member)
                    } label: {
                        MemberRow(member: member, isLinked: hasMatchingAccount(member))
                    }
                }
                .onDelete { offsets in
                    pendingDeletion = offsets.map { members[$0] }
                }
            }
        }
        .navigationTitle("Mitglieder")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await SyncOrchestrationService.syncAll(modelContext: modelContext)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAdd = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Neues Mitglied")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showImporter = true } label: { Image(systemName: "square.and.arrow.down") }
                    .accessibilityLabel("Mitglieder importieren")
            }
            ToolbarItem(placement: .topBarTrailing) {
                if let exportURL {
                    ShareLink(item: exportURL) { Image(systemName: "square.and.arrow.up") }
                        .accessibilityLabel("Mitglieder exportieren")
                }
            }
        }
        .sheet(isPresented: $showAdd) {
            AddMemberView()
        }
        .confirmationDialog("Mitglied löschen?", isPresented: deletionDialogShown, titleVisibility: .visible) {
            Button("Löschen", role: .destructive) {
                deleteMembers(pendingDeletion)
                pendingDeletion = []
            }
            Button("Abbrechen", role: .cancel) { pendingDeletion = [] }
        } message: {
            Text("Der Eintrag wird aus der Vereinskartei entfernt. Team-Zuordnungen dieser Person werden ebenfalls gelöscht.")
        }
        .task(id: members.map(\.id)) {
            exportURL = try? MemberImportExport.exportFile(members: members)
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
            handleImport(result)
        }
        .alert("Import", isPresented: importAlertShown) {
            Button("OK") { importResultMessage = nil }
        } message: {
            Text(importResultMessage ?? "")
        }
        .alert("Fehler", isPresented: failureAlertShown) {
            Button("OK") { failureSignal.clear() }
        } message: {
            Text(failureSignal.message ?? "")
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
                let outcome = MemberImportExport.importMembers(from: data, into: members, modelContext: modelContext)
                importResultMessage = outcome.summary
            } catch {
                importResultMessage = "Datei konnte nicht gelesen werden: \(error.localizedDescription)"
            }
        }
    }

    private func hasMatchingAccount(_ member: Member) -> Bool {
        users.contains { Member.matches(email: $0.email, firstName: $0.firstName, lastName: $0.lastName, in: [member]) }
    }

    private func deleteMembers(_ toDelete: [Member]) {
        for member in toDelete {
            MemberService.delete(member, modelContext: modelContext)
        }
        // Re-fetched rather than using the `members` @Query array directly —
        // SwiftUI's @Query refresh isn't guaranteed to have landed yet at
        // this exact point, so a fresh fetch is the only way to be sure the
        // backup reflects the roster with these entries actually removed.
        let remaining = (try? modelContext.fetch(FetchDescriptor<Member>())) ?? []
        MemberBackup.snapshot(members: remaining)
    }
}

struct MemberRow: View {
    let member: Member
    let isLinked: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(member.fullName)
                    .font(.headline)
                if !member.fullAddress.isEmpty {
                    Text(member.fullAddress)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if isLinked {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .help("Mit einem Benutzerkonto verknüpft")
                    // .help() only reaches pointer/Catalyst UIs — this icon is the
                    // only place this status is conveyed, so VoiceOver needs its
                    // own label rather than the auto-derived SF Symbol name.
                    .accessibilityLabel("Mit einem Benutzerkonto verknüpft")
            }
        }
        .padding(.vertical, 4)
    }
}

struct MemberDetailView: View {
    @Bindable var member: Member
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section("Mitglied") {
                TextField("Vorname", text: $member.firstName)
                TextField("Nachname", text: $member.lastName)
                TextField("Titel", text: $member.title)
                Picker("Geschlecht", selection: $member.gender) {
                    Text("–").tag("")
                    Text("weiblich").tag("f")
                    Text("männlich").tag("m")
                }
                OptionalDatePicker(label: "Geburtsdatum", date: $member.birthDate)
                TextField("Straße", text: $member.street)
                TextField("PLZ", text: $member.zip)
                    .keyboardType(.numberPad)
                TextField("Ort", text: $member.city)
                TextField("Land", text: $member.country)
            }
            Section("Kontakt") {
                TextField("E-Mail", text: $member.email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Telefon", text: $member.phone)
                    .keyboardType(.phonePad)
            }
            Section("Mitgliedschaft") {
                Toggle("Mitglied des Grazer VSC", isOn: $member.memberOfGVSC)
                TextField("Mitgliedsnummer", text: $member.memberNumber)
                DatePicker("Beigetreten", selection: $member.joinedAt, displayedComponents: .date)
                TextField("Sport-ID", text: $member.sportId)
                TextField("SVNR", text: $member.svnr)
                if !Validation.isPlausibleAustrianSVNR(member.svnr) {
                    Label("SVNR-Format ungewöhnlich", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                TextField("IBAN", text: $member.iban)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                if !Validation.ibanChecksumIsValid(member.iban) {
                    Label("IBAN-Prüfsumme ungültig", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                OptionalDatePicker(label: "Letzte sportärztl. Untersuchung", date: $member.lastMedicalExamination)
                TextField("Standardfunktion", text: $member.defaultFunction)
            }
            Section("Notizen") {
                TextField("Notizen", text: $member.notes, axis: .vertical)
                    .lineLimit(3...6)
            }
        }
        .navigationTitle(member.fullName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Fertig") { dismiss() }
            }
        }
        .onDisappear {
            MemberService.save(member, modelContext: modelContext)
        }
    }
}

/// A DatePicker that can represent "no date set" via a toggle — SwiftUI's
/// DatePicker has no built-in nil state, and `birthDate`/
/// `lastMedicalExamination` are optional since much of the club's real
/// roster data omits them (see Member's doc comment in Models.swift).
struct OptionalDatePicker: View {
    let label: String
    @Binding var date: Date?

    var body: some View {
        Toggle(label, isOn: Binding(
            get: { date != nil },
            set: { date = $0 ? (date ?? Date()) : nil }
        ))
        if date != nil {
            DatePicker(label, selection: Binding(
                get: { date ?? Date() },
                set: { date = $0 }
            ), displayedComponents: .date)
            .labelsHidden()
        }
    }
}

/// Self-service editing of a member's own Grazer VSC roster entry — reachable
/// from AccountView's "Vereinsdaten bearbeiten" button for any account
/// matched to a roster entry (see AccountView.matchedMember), or freshly
/// created via AccountView's "Mitgliedschaft beantragen" flow for one that
/// isn't yet. Deliberately narrower than admin's MemberDetailView above:
/// still no "Mitgliedschaft" administrative fields (memberNumber/joinedAt/
/// memberOfGVSC are admin-assigned/confirmed, not self-declared —
/// memberOfGVSC in particular is exactly the "has an admin confirmed this
/// person as an actual club member" flag, so self-editing it would defeat
/// its own purpose) and no "Notizen" (may hold private admin remarks) — but
/// DOES include sportId/svnr/iban/lastMedicalExamination now (moved from
/// admin-only per user request "every user should get the possibility to
/// enter all data"), since those are personal identity/financial/health
/// facts only the member themselves actually knows, unlike defaultFunction
/// (an admin's team-assignment categorization of this person, stays
/// admin-only) or the membership-status fields above.
struct MyMemberView: View {
    @Bindable var member: Member
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Mitglied") {
                    TextField("Vorname", text: $member.firstName)
                    TextField("Nachname", text: $member.lastName)
                    TextField("Titel", text: $member.title)
                    Picker("Geschlecht", selection: $member.gender) {
                        Text("–").tag("")
                        Text("weiblich").tag("f")
                        Text("männlich").tag("m")
                    }
                    OptionalDatePicker(label: "Geburtsdatum", date: $member.birthDate)
                    TextField("Straße", text: $member.street)
                    TextField("PLZ", text: $member.zip)
                        .keyboardType(.numberPad)
                    TextField("Ort", text: $member.city)
                    TextField("Land", text: $member.country)
                }
                Section("Kontakt") {
                    TextField("E-Mail", text: $member.email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Telefon", text: $member.phone)
                        .keyboardType(.phonePad)
                }
                // Same fields/validation as MemberDetailView's "Mitgliedschaft"
                // section, minus the admin-assigned ones (see this type's doc
                // comment) — kept as its own section rather than folded into
                // "Kontakt" since these are federation/payout data, not
                // everyday contact info.
                Section("Sportverband & Zahlungsdaten") {
                    TextField("Sport-ID", text: $member.sportId)
                    TextField("SVNR", text: $member.svnr)
                    if !Validation.isPlausibleAustrianSVNR(member.svnr) {
                        Label("SVNR-Format ungewöhnlich", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    TextField("IBAN", text: $member.iban)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    if !Validation.ibanChecksumIsValid(member.iban) {
                        Label("IBAN-Prüfsumme ungültig", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    OptionalDatePicker(label: "Letzte sportärztl. Untersuchung", date: $member.lastMedicalExamination)
                }
            }
            .navigationTitle("Vereinsdaten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
            .onDisappear {
                MemberService.save(member, modelContext: modelContext)
            }
        }
    }
}

struct AddMemberView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var firstName = ""
    @State private var lastName = ""
    @State private var street = ""
    @State private var zip = ""
    @State private var city = ""
    @State private var country = ""
    @State private var email = ""
    @State private var phone = ""
    @State private var memberNumber = ""
    @State private var joinedAt = Date()
    @State private var notes = ""
    @State private var gender = ""
    @State private var title = ""
    @State private var birthDate: Date?
    @State private var sportId = ""
    @State private var svnr = ""
    @State private var iban = ""
    @State private var lastMedicalExamination: Date?
    @State private var defaultFunction = ""
    @State private var memberOfGVSC = true

    var body: some View {
        NavigationStack {
            Form {
                Section("Mitglied") {
                    TextField("Vorname", text: $firstName)
                    TextField("Nachname", text: $lastName)
                    TextField("Titel", text: $title)
                    Picker("Geschlecht", selection: $gender) {
                        Text("–").tag("")
                        Text("weiblich").tag("f")
                        Text("männlich").tag("m")
                    }
                    OptionalDatePicker(label: "Geburtsdatum", date: $birthDate)
                    TextField("Straße", text: $street)
                    TextField("PLZ", text: $zip)
                        .keyboardType(.numberPad)
                    TextField("Ort", text: $city)
                    TextField("Land", text: $country)
                }
                Section("Kontakt") {
                    TextField("E-Mail", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Telefon", text: $phone)
                        .keyboardType(.phonePad)
                }
                Section("Mitgliedschaft") {
                    Toggle("Mitglied des Grazer VSC", isOn: $memberOfGVSC)
                    TextField("Mitgliedsnummer", text: $memberNumber)
                    DatePicker("Beigetreten", selection: $joinedAt, displayedComponents: .date)
                    TextField("Sport-ID", text: $sportId)
                    TextField("SVNR", text: $svnr)
                    if !Validation.isPlausibleAustrianSVNR(svnr) {
                        Label("SVNR-Format ungewöhnlich", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    TextField("IBAN", text: $iban)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    if !Validation.ibanChecksumIsValid(iban) {
                        Label("IBAN-Prüfsumme ungültig", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    OptionalDatePicker(label: "Letzte sportärztl. Untersuchung", date: $lastMedicalExamination)
                    TextField("Standardfunktion", text: $defaultFunction)
                }
                Section("Notizen") {
                    TextField("Notizen", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("Neues Mitglied")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") {
                        let member = Member(firstName: firstName, lastName: lastName, street: street,
                                             zip: zip, city: city, country: country, email: email, phone: phone,
                                             memberNumber: memberNumber, joinedAt: joinedAt, notes: notes,
                                             gender: gender, title: title, birthDate: birthDate,
                                             sportId: sportId, svnr: svnr, iban: iban,
                                             lastMedicalExamination: lastMedicalExamination,
                                             defaultFunction: defaultFunction, memberOfGVSC: memberOfGVSC)
                        modelContext.insert(member)
                        MemberService.save(member, modelContext: modelContext)
                        let allMembers = (try? modelContext.fetch(FetchDescriptor<Member>())) ?? []
                        MemberBackup.snapshot(members: allMembers)
                        dismiss()
                    }
                    .disabled(firstName.trimmingCharacters(in: .whitespaces).isEmpty ||
                              lastName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

/// Admin-only combined "Personen" list, pushed from `VereinView`'s hub —
/// one row per real person, merging app accounts (`User`) and roster
/// entries (`Member`). Reachable only from the admin hub, so no extra role
/// gate here.
///
/// Dedup is best-effort: a `User` is folded together with the `Member` it
/// matches via `Member.first(matching:)` (email first, else first+last
/// name). Because that match is fuzzy, a `User` synced from another device
/// — whose `email` is never synced (see CloudKitSync) — can only be paired
/// by name, and two different people who share a first+last name collapse
/// into one row. A persistent User↔Member link is the real fix (out of
/// scope here).
struct PersonenListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\User.lastName), SortDescriptor(\User.firstName)])
    private var users: [User]
    @Query(sort: [SortDescriptor(\Member.lastName), SortDescriptor(\Member.firstName)])
    private var members: [Member]
    @State private var searchText = ""
    @State private var filter: PersonFilter = .all

    enum PersonFilter: String, CaseIterable, Identifiable {
        case all = "Alle"
        case withAccount = "Mit Konto"
        case rosterOnly = "Nur Kartei"
        case grazerVSC = "Grazer VSC"
        var id: String { rawValue }
    }

    private var people: [PersonEntry] {
        var rows: [PersonEntry] = []
        var matchedMemberIDs = Set<UUID>()

        for user in users {
            let match = Member.first(matching: user, in: members)
            if let match { matchedMemberIDs.insert(match.id) }
            rows.append(PersonEntry(
                id: "user-\(user.id.uuidString)",
                lastName: user.lastName,
                firstName: user.firstName,
                name: user.displayName.isEmpty ? "?" : user.displayName,
                hasAccount: true,
                onRoster: match != nil,
                roleLabel: user.role.displayLabel,
                memberOfGVSC: match?.memberOfGVSC ?? user.isGrazerVSCMember,
                teamCount: user.memberships.count,
                member: match
            ))
        }

        for member in members where !matchedMemberIDs.contains(member.id) {
            rows.append(PersonEntry(
                id: "member-\(member.id.uuidString)",
                lastName: member.lastName,
                firstName: member.firstName,
                name: member.fullName.isEmpty ? "?" : member.fullName,
                hasAccount: false,
                onRoster: true,
                roleLabel: nil,
                memberOfGVSC: member.memberOfGVSC,
                teamCount: member.teamMemberships.count,
                member: member
            ))
        }

        let filtered = rows.filter { row in
            switch filter {
            case .all: return true
            case .withAccount: return row.hasAccount
            case .rosterOnly: return row.onRoster && !row.hasAccount
            case .grazerVSC: return row.memberOfGVSC
            }
        }
        let needle = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        let searched = needle.isEmpty ? filtered : filtered.filter { $0.name.lowercased().contains(needle) }
        return searched.sorted {
            let byLast = $0.lastName.localizedCaseInsensitiveCompare($1.lastName)
            if byLast != .orderedSame { return byLast == .orderedAscending }
            return $0.firstName.localizedCaseInsensitiveCompare($1.firstName) == .orderedAscending
        }
    }

    var body: some View {
        List {
            Section {
                Picker("Filter", selection: $filter) {
                    ForEach(PersonFilter.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            if people.isEmpty {
                ContentUnavailableView("Keine Personen", systemImage: "person.crop.rectangle.stack")
            } else {
                ForEach(people) { row in
                    if let member = row.member {
                        NavigationLink { MemberDetailView(member: member) } label: { rowLabel(row) }
                    } else {
                        rowLabel(row)
                    }
                }
            }
        }
        .navigationTitle("Personen")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Name")
        .refreshable {
            await SyncOrchestrationService.syncAll(modelContext: modelContext)
        }
    }

    @ViewBuilder
    private func rowLabel(_ row: PersonEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(row.name).font(.headline)
            HStack(spacing: 6) {
                if row.hasAccount { capsuleTag("Konto", .blue) }
                if row.onRoster { capsuleTag("Kartei", .green) }
                if row.memberOfGVSC {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                        .accessibilityLabel("Grazer VSC")
                }
            }
            HStack(spacing: 8) {
                if let roleLabel = row.roleLabel {
                    Text(roleLabel)
                }
                Text(row.teamCount == 1 ? "1 Team" : "\(row.teamCount) Teams")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private func capsuleTag(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.caption2).bold()
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
}

private struct PersonEntry: Identifiable {
    let id: String
    let lastName: String
    let firstName: String
    let name: String
    let hasAccount: Bool
    let onRoster: Bool
    let roleLabel: String?
    let memberOfGVSC: Bool
    let teamCount: Int
    let member: Member?
}
