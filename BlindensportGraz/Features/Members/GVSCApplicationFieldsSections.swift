import SwiftUI

/// The fields of the GVSC Beitrittserklärung beyond the basic roster data —
/// shared by `Member` (admin edits it directly) and `MemberChangeRequest`
/// (a member's own proposal), so both forms show one set of sections.
protocol GVSCApplicationFields: AnyObject {
    var birthDate: Date? { get }
    var membershipType: String { get set }
    var citizenship: String { get set }
    var mobile: String { get set }
    var guardianFirstName: String { get set }
    var guardianLastName: String { get set }
    var guardianStreet: String { get set }
    var guardianZip: String { get set }
    var guardianCity: String { get set }
    var guardianPhone: String { get set }
    var guardianMobile: String { get set }
    var guardianEmail: String { get set }
    var disabilityType: String { get set }
    var disabilityClass: String { get set }
    var disabilityCause: String { get set }
    var consentDataTransfer: Bool? { get set }
    var consentPhotos: Bool? { get set }
}

extension GVSCApplicationFields {
    /// Under 18 on `date` — the Beitrittserklärung then asks for a guardian.
    /// Unknown birth date counts as adult.
    func isMinor(on date: Date = .now) -> Bool {
        guard let birthDate,
              let age = Calendar.current.dateComponents([.year], from: birthDate, to: date).year else { return false }
        return age < 18
    }
}

extension Member: GVSCApplicationFields {}
extension MemberChangeRequest: GVSCApplicationFields {}

nonisolated enum GVSCMembershipType {
    static let active = "active"
    static let supporting = "supporting"
}

/// Form sections for `GVSCApplicationFields`. `includesPrivate` shows the
/// protected disability/consent fields (same rule as SVNR/IBAN).
struct GVSCApplicationFieldsSections<Model: GVSCApplicationFields>: View {
    let model: Model
    let includesPrivate: Bool

    private var hasGuardian: Bool {
        !(model.guardianFirstName + model.guardianLastName + model.guardianStreet + model.guardianZip
          + model.guardianCity + model.guardianPhone + model.guardianMobile + model.guardianEmail).isEmpty
    }

    var body: some View {
        Section("Beitrittserklärung Grazer VSC") {
            Picker("Mitgliedsart", selection: binding(\.membershipType)) {
                Text("–").tag("")
                Text("aktiv").tag(GVSCMembershipType.active)
                Text("fördernd").tag(GVSCMembershipType.supporting)
            }
            TextField("Staatsbürgerschaft", text: binding(\.citizenship))
            TextField("Mobilnummer", text: binding(\.mobile))
                .keyboardType(.phonePad)
        }
        if includesPrivate {
            Section {
                TextField("Art der Behinderung", text: binding(\.disabilityType))
                TextField("Behinderungsklasse", text: binding(\.disabilityClass))
                TextField("Behinderung durch (Arbeit, Freizeit)", text: binding(\.disabilityCause))
            } header: {
                Text("Behinderung")
            }
            Section {
                consentPicker("Datenweitergabe an Fach- und Dachverbände", binding(\.consentDataTransfer))
                consentPicker("Foto- und Videoaufnahmen", binding(\.consentPhotos))
            } header: {
                Text("Einwilligungen")
            }
        }
        if model.isMinor() || hasGuardian {
            Section {
                TextField("Vorname", text: binding(\.guardianFirstName))
                TextField("Nachname", text: binding(\.guardianLastName))
                TextField("Straße, Hausnummer", text: binding(\.guardianStreet))
                TextField("PLZ", text: binding(\.guardianZip))
                    .keyboardType(.numberPad)
                TextField("Wohnort", text: binding(\.guardianCity))
                TextField("Telefon", text: binding(\.guardianPhone))
                    .keyboardType(.phonePad)
                TextField("Mobilnummer", text: binding(\.guardianMobile))
                    .keyboardType(.phonePad)
                TextField("E-Mail", text: binding(\.guardianEmail))
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("Gesetzliche:r Vertreter:in")
            } footer: {
                Text("Nur bei minderjährigen Mitgliedern.")
            }
        }
    }

    private func consentPicker(_ label: LocalizedStringKey, _ selection: Binding<Bool?>) -> some View {
        Picker(label, selection: selection) {
            Text("–").tag(Bool?.none)
            Text("Ja").tag(Bool?.some(true))
            Text("Nein").tag(Bool?.some(false))
        }
    }

    /// Works for both an inserted model and a not-yet-inserted draft (see
    /// MyMemberView.bindingFor).
    private func binding<Value>(_ keyPath: ReferenceWritableKeyPath<Model, Value>) -> Binding<Value> {
        Binding(get: { model[keyPath: keyPath] }, set: { model[keyPath: keyPath] = $0 })
    }
}
