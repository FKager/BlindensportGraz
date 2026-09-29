import SwiftUI
import SwiftData
import UniformTypeIdentifiers

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
