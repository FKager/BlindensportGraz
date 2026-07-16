import SwiftUI
import SwiftData

/// Admin-only management of the "Grazer VSC" club membership roster. New app
/// accounts are auto-flagged as club members by matching against this roster
/// (see ClubMember.checkMembership in Models.swift).
struct ClubMembersListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ClubMember.fullName) private var members: [ClubMember]
    @Query private var users: [User]
    @State private var showAdd = false

    var body: some View {
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
        .refreshable {
            await CloudKitSync.shared.syncAll(modelContext: modelContext)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAdd = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showAdd) {
            AddClubMemberView()
        }
    }

    private func hasMatchingAccount(_ member: ClubMember) -> Bool {
        users.contains { ClubMember.matches(email: $0.email, displayName: $0.displayName, in: [member]) }
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
                if !member.address.isEmpty {
                    Text(member.address)
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

    var body: some View {
        Form {
            Section("Mitglied") {
                TextField("Name", text: $member.fullName)
                TextField("Adresse", text: $member.address, axis: .vertical)
                    .lineLimit(2...4)
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
        .onDisappear {
            try? modelContext.save()
            CloudKitSync.shared.pushClubMember(member)
        }
    }
}

struct AddClubMemberView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var fullName = ""
    @State private var address = ""
    @State private var email = ""
    @State private var phone = ""
    @State private var memberNumber = ""
    @State private var joinedAt = Date()
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Mitglied") {
                    TextField("Name", text: $fullName)
                    TextField("Adresse", text: $address, axis: .vertical)
                        .lineLimit(2...4)
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
                        let member = ClubMember(fullName: fullName, address: address, email: email,
                                                 phone: phone, memberNumber: memberNumber,
                                                 joinedAt: joinedAt, notes: notes)
                        modelContext.insert(member)
                        try? modelContext.save()
                        CloudKitSync.shared.pushClubMember(member)
                        dismiss()
                    }
                    .disabled(fullName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
