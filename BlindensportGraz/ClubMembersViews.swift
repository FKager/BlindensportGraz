import SwiftUI
import SwiftData

/// Admin-only management of the "Grazer VSC" club membership roster. New app
/// accounts are auto-flagged as club members by matching against this roster
/// (see ClubMember.checkMembership in Models.swift). Presented as a sheet from
/// AccountView's "Grazer VSC verwalten" button, not as its own tab (see
/// MainTabView's comment for why -- too many top-level tabs pushed it into
/// iOS's auto-collapsed "More" screen), so it's self-contained with its own
/// NavigationStack and a dismiss button, unlike a tab-hosted view.
struct ClubMembersListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: [SortDescriptor(\ClubMember.lastName), SortDescriptor(\ClubMember.firstName)])
    private var members: [ClubMember]
    @Query private var users: [User]
    @State private var showAdd = false

    var body: some View {
        NavigationStack {
            List {
                if members.isEmpty {
                    ContentUnavailableView("Keine Vereinsmitglieder",
                                           systemImage: "building.columns",
                                           description: Text("Lege ein neues Mitglied des Grazer VSC an."))
                } else {
                    ForEach(members) { member in
                        NavigationLink {
                            ClubMemberDetailView(member: member)
                        } label: {
                            ClubMemberRow(member: member, isLinked: hasMatchingAccount(member))
                        }
                    }
                    .onDelete(perform: deleteMembers)
                }
            }
            .navigationTitle("Grazer VSC")
            .navigationBarTitleDisplayMode(.inline)
            .refreshable {
                await CloudKitSync.shared.syncAll(modelContext: modelContext)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showAdd) {
                AddClubMemberView()
            }
        }
    }

    private func hasMatchingAccount(_ member: ClubMember) -> Bool {
        users.contains { ClubMember.matches(email: $0.email, firstName: $0.firstName, lastName: $0.lastName, in: [member]) }
    }

    private func deleteMembers(at offsets: IndexSet) {
        for index in offsets {
            let member = members[index]
            CloudKitSync.shared.deleteClubMember(member.id)
            modelContext.delete(member)
        }
        try? modelContext.save()
    }
}

struct ClubMemberRow: View {
    let member: ClubMember
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
            }
        }
        .padding(.vertical, 4)
    }
}

struct ClubMemberDetailView: View {
    @Bindable var member: ClubMember
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section("Mitglied") {
                TextField("Vorname", text: $member.firstName)
                TextField("Nachname", text: $member.lastName)
                TextField("Straße", text: $member.street)
                TextField("PLZ", text: $member.zip)
                    .keyboardType(.numberPad)
                TextField("Ort", text: $member.city)
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
                TextField("Mitgliedsnummer", text: $member.memberNumber)
                DatePicker("Beigetreten", selection: $member.joinedAt, displayedComponents: .date)
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
            try? modelContext.save()
            CloudKitSync.shared.pushClubMember(member)
        }
    }
}

/// Self-service editing of a member's own Grazer VSC roster entry — reachable
/// from AccountView's "Vereinsdaten bearbeiten" button for any account with
/// isGrazerVSCMember == true. Deliberately narrower than admin's
/// ClubMemberDetailView above: no "Mitgliedschaft" (memberNumber/joinedAt are
/// admin-assigned) and no "Notizen" (may hold private admin remarks about the
/// member) — only personal/contact fields are self-editable.
struct MyClubMemberView: View {
    @Bindable var member: ClubMember
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Mitglied") {
                    TextField("Vorname", text: $member.firstName)
                    TextField("Nachname", text: $member.lastName)
                    TextField("Straße", text: $member.street)
                    TextField("PLZ", text: $member.zip)
                        .keyboardType(.numberPad)
                    TextField("Ort", text: $member.city)
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
                try? modelContext.save()
                CloudKitSync.shared.pushClubMember(member)
            }
        }
    }
}

struct AddClubMemberView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var firstName = ""
    @State private var lastName = ""
    @State private var street = ""
    @State private var zip = ""
    @State private var city = ""
    @State private var email = ""
    @State private var phone = ""
    @State private var memberNumber = ""
    @State private var joinedAt = Date()
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Mitglied") {
                    TextField("Vorname", text: $firstName)
                    TextField("Nachname", text: $lastName)
                    TextField("Straße", text: $street)
                    TextField("PLZ", text: $zip)
                        .keyboardType(.numberPad)
                    TextField("Ort", text: $city)
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
                    TextField("Mitgliedsnummer", text: $memberNumber)
                    DatePicker("Beigetreten", selection: $joinedAt, displayedComponents: .date)
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
                        let member = ClubMember(firstName: firstName, lastName: lastName, street: street,
                                                 zip: zip, city: city, email: email, phone: phone,
                                                 memberNumber: memberNumber, joinedAt: joinedAt, notes: notes)
                        modelContext.insert(member)
                        try? modelContext.save()
                        CloudKitSync.shared.pushClubMember(member)
                        dismiss()
                    }
                    .disabled(firstName.trimmingCharacters(in: .whitespaces).isEmpty ||
                              lastName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
