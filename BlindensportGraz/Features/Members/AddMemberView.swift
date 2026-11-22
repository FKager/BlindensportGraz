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

    /// What's missing before saving; shown above the buttons and read out.
    @State private var formMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                FormTitleHeader(title: "Neues Mitglied")
                Section(heading: "Mitglied") {
                    StackedField(label: "Vorname", text: $firstName)
                    StackedField(label: "Nachname", text: $lastName)
                    StackedField(label: "Titel", text: $title)
                    Picker("Geschlecht", selection: $gender) {
                        Text("–").tag("")
                        Text("weiblich").tag("f")
                        Text("männlich").tag("m")
                    }
                    OptionalDatePicker(label: "Geburtsdatum", date: $birthDate)
                    StackedField(label: "Straße", text: $street)
                    StackedField(label: "PLZ", text: $zip)
                        .keyboardType(.numberPad)
                    StackedField(label: "Ort", text: $city)
                    StackedField(label: "Land", text: $country)
                }
                Section(heading: "Kontakt") {
                    StackedField(label: "E-Mail", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    StackedField(label: "Telefon", text: $phone)
                        .keyboardType(.phonePad)
                }
                Section(heading: "Mitgliedschaft") {
                    Toggle("Mitglied des Grazer VSC", isOn: $memberOfGVSC)
                    StackedField(label: "Mitgliedsnummer", text: $memberNumber)
                    DatePicker("Beigetreten", selection: $joinedAt, displayedComponents: .date)
                    StackedField(label: "Sport-ID", text: $sportId)
                    StackedField(label: "SVNR", text: $svnr)
                    if !Validation.isPlausibleAustrianSVNR(svnr) {
                        Label("SVNR-Format ungewöhnlich", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(Theme.Palette.warning)
                    }
                    StackedField(label: "IBAN", text: $iban)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    if !Validation.ibanChecksumIsValid(iban) {
                        Label("IBAN-Prüfsumme ungültig", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(Theme.Palette.warning)
                    }
                    OptionalDatePicker(label: "Letzte sportärztl. Untersuchung", date: $lastMedicalExamination)
                    StackedField(label: "Standardfunktion", text: $defaultFunction)
                }
                Section(heading: "Notizen") {
                    StackedField(label: "Notizen", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
                FormActionButtons(primaryTitle: "Speichern", cancelTitle: "Abbrechen", message: formMessage,
                                  onPrimary: attemptSave, onCancel: { dismiss() })
            }
        }
    }

    /// Speichern is never greyed out: it says what's missing instead.
    private func attemptSave() {
        if firstName.trimmingCharacters(in: .whitespaces).isEmpty ||
                              lastName.trimmingCharacters(in: .whitespaces).isEmpty {
            formMessage = String(localized: "Bitte gib Vor- und Nachnamen ein.")
            AccessibilityNotification.Announcement(formMessage ?? "").post()
            return
        }
        formMessage = nil
        save()
    }

    private func save() {
        let member = Member(firstName: firstName, lastName: lastName, street: street,
                             zip: zip, city: city, country: country, email: email, phone: phone,
                             memberNumber: memberNumber, joinedAt: joinedAt, notes: notes,
                             gender: gender, title: title, birthDate: birthDate,
                             sportId: sportId, svnr: svnr, iban: iban,
                             lastMedicalExamination: lastMedicalExamination,
                             defaultFunction: defaultFunction, memberOfGVSC: memberOfGVSC)
        modelContext.insert(member)
        MemberService.save(member, modelContext: modelContext)
        dismiss()
    }
}
