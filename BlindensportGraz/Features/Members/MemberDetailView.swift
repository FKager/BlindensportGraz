import SwiftUI
import SwiftData
import UniformTypeIdentifiers

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
