import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct MemberDetailView: View {
    @Bindable var member: Member
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var showApplication = false
    @Query private var approvals: [AccountApproval]

    /// The account an admin linked to this entry — its profile photo goes
    /// with the Beitrittserklärung.
    private var linkedUserID: UUID? {
        approvals.filter { $0.memberID == member.id }.max { $0.approvedAt < $1.approvedAt }?.userID
    }

    var body: some View {
        Form {
            Section(heading: "Mitglied") {
                StackedField(label: "Vorname", text: $member.firstName)
                StackedField(label: "Nachname", text: $member.lastName)
                StackedField(label: "Titel", text: $member.title)
                Picker("Geschlecht", selection: $member.gender) {
                    Text("–").tag("")
                    Text("weiblich").tag("f")
                    Text("männlich").tag("m")
                }
                OptionalDatePicker(label: "Geburtsdatum", date: $member.birthDate)
                StackedField(label: "Straße", text: $member.street)
                StackedField(label: "PLZ", text: $member.zip)
                    .keyboardType(.numberPad)
                StackedField(label: "Ort", text: $member.city)
                StackedField(label: "Land", text: $member.country)
            }
            Section(heading: "Kontakt") {
                StackedField(label: "E-Mail", text: $member.email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                StackedField(label: "Telefon", text: $member.phone)
                    .keyboardType(.phonePad)
            }
            Section(heading: "Mitgliedschaft") {
                Picker("Status", selection: $member.status) {
                    ForEach(MemberStatus.allCases, id: \.rawValue) { status in
                        Text(status.label).tag(status.rawValue)
                    }
                }
                Toggle("Mitglied des Grazer VSC", isOn: $member.memberOfGVSC)
                if !member.memberOfGVSC, let appliedAt = member.gvscAppliedAt {
                    Label("Beitritt beantragt am \(appliedAt.formatted(date: .abbreviated, time: .omitted))",
                          systemImage: "envelope.badge")
                        .foregroundStyle(Theme.Palette.warning)
                    Button {
                        confirmMembership()
                    } label: {
                        Label("Mitgliedschaft bestätigen", systemImage: "checkmark.seal")
                    }
                    .accessibilityHint("Schaltet „Mitglied des Grazer VSC“ ein und setzt „Beigetreten“ auf heute.")
                }
                if !member.memberOfGVSC {
                    Button {
                        showApplication = true
                    } label: {
                        Label("Beitrittserklärung senden", systemImage: "doc.richtext")
                    }
                }
                StackedField(label: "Mitgliedsnummer", text: $member.memberNumber)
                DatePicker("Beigetreten", selection: $member.joinedAt, displayedComponents: .date)
                StackedField(label: "Sport-ID", text: $member.sportId)
                StackedField(label: "SVNR", text: $member.svnr)
                if !Validation.isPlausibleAustrianSVNR(member.svnr) {
                    Label("SVNR-Format ungewöhnlich", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(Theme.Palette.warning)
                }
                StackedField(label: "IBAN", text: $member.iban)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                if !Validation.ibanChecksumIsValid(member.iban) {
                    Label("IBAN-Prüfsumme ungültig", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(Theme.Palette.warning)
                }
                OptionalDatePicker(label: "Letzte sportärztl. Untersuchung", date: $member.lastMedicalExamination)
                StackedField(label: "Standardfunktion", text: $member.defaultFunction)
            }
            GVSCApplicationFieldsSections(model: member, includesPrivate: true)
            Section(heading: "Notizen") {
                StackedField(label: "Notizen", text: $member.notes, axis: .vertical)
                    .lineLimit(3...6)
            }
            FormActionButtons(primaryTitle: "Fertig", cancelTitle: nil, onPrimary: { dismiss() })
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
        .sheet(isPresented: $showApplication) {
            GVSCApplicationView(member: member, photoUserID: linkedUserID)
        }
    }

    /// The signed form has arrived: the entry becomes a club member today.
    private func confirmMembership() {
        member.memberOfGVSC = true
        member.joinedAt = .now
        MemberService.save(member, modelContext: modelContext)
    }
}
