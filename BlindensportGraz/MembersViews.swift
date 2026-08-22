import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// "Benutzerverwaltung" (user/member administration), formerly the
/// admin-only "Grazer VSC" club roster screen. New app accounts are
/// auto-flagged as club members by matching against this roster (see
/// Member.checkMembership in Models.swift). `Member.memberOfGVSC` makes
/// club membership an explicit per-entry flag rather than something implied
/// by mere presence on the roster, since this list also carries
/// helpers/coaches who aren't necessarily formal members. Its own top-level
/// tab (admin/root only, see MainTabView), retained as a self-contained
/// NavigationStack with a "Fertig" dismiss button since it's also still
/// presentable as a sheet elsewhere. Also hosts access to `UserListView`
/// (account/role administration, "Benutzer verwalten" toolbar button) --
/// both admin-facing user-management screens live under this one tab now
/// instead of being split between here and AccountView.
struct MembersListView: View {
    let currentUser: User
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: [SortDescriptor(\Member.lastName), SortDescriptor(\Member.firstName)])
    private var members: [Member]
    @Query private var users: [User]
    @State private var showAdd = false
    @State private var showUserList = false
    @State private var showRoleChangeLog = false
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

    var body: some View {
        NavigationStack {
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
                    .onDelete(perform: deleteMembers)
                }
            }
            .navigationTitle("Benutzerverwaltung")
            .navigationBarTitleDisplayMode(.inline)
            .refreshable {
                await SyncOrchestrationService.syncAll(modelContext: modelContext)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Neues Mitglied")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showUserList = true } label: { Image(systemName: "person.2.fill") }
                        .accessibilityLabel("Benutzer verwalten")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showRoleChangeLog = true } label: { Image(systemName: "clock.arrow.circlepath") }
                        .accessibilityLabel("Rollenänderungen")
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
            .sheet(isPresented: $showUserList) {
                UserListView(currentUser: currentUser)
            }
            .sheet(isPresented: $showRoleChangeLog) {
                RoleChangeLogView()
            }
            .task(id: members.map(\.id)) {
                exportURL = try? MemberImportExport.exportFile(members: members)
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
            .alert("Fehler", isPresented: Binding(
                get: { failureSignal.message != nil },
                set: { if !$0 { failureSignal.clear() } }
            )) {
                Button("OK") { failureSignal.clear() }
            } message: {
                Text(failureSignal.message ?? "")
            }
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

    private func deleteMembers(at offsets: IndexSet) {
        for index in offsets {
            MemberService.delete(members[index], modelContext: modelContext)
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
/// from AccountView's "Vereinsdaten bearbeiten" button for any account with
/// isGrazerVSCMember == true. Deliberately narrower than admin's
/// MemberDetailView above: no "Mitgliedschaft" (memberNumber/joinedAt/
/// memberOfGVSC are admin-assigned) and no "Notizen" (may hold private admin
/// remarks about the member) — only personal/contact fields are self-editable.
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
