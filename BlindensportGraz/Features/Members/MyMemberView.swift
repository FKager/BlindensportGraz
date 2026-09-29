import SwiftUI
import SwiftData
import UniformTypeIdentifiers

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
/// Self-service "Vereinsdaten" edit — architecture-review.md §5 P2. Does
/// **not** write to the live `member` record directly (that used to take
/// effect immediately, including SVNR/IBAN, with no review at all); it
/// edits a `MemberChangeRequest` draft instead, submitted for an admin to
/// approve/reject. If this member already has a pending request, the draft
/// continues editing THAT request (so repeatedly opening/adjusting before
/// it's reviewed doesn't pile up duplicates) rather than starting a new one.
struct MyMemberView: View {
    let member: Member
    let currentUser: User?
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var allRequests: [MemberChangeRequest]

    @State private var draft: MemberChangeRequest?

    private var pendingRequest: MemberChangeRequest? {
        allRequests.first { $0.memberID == member.id && $0.status == MemberChangeRequest.pendingStatus }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let draft {
                    form(for: draft)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Vereinsdaten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") {
                        submitIfChanged()
                        dismiss()
                    }
                }
            }
            .onAppear {
                guard draft == nil else { return }
                draft = pendingRequest ?? MemberChangeRequest.snapshot(of: member, requestedBy: currentUser?.id.uuidString ?? "")
            }
        }
    }

    @ViewBuilder
    private func form(for draft: MemberChangeRequest) -> some View {
        Form {
            if pendingRequest != nil {
                Section {
                    Label("Eine frühere Änderung wartet noch auf Bestätigung durch eine Administration. Weitere Anpassungen hier aktualisieren diesen Antrag.",
                          systemImage: "clock.badge.checkmark")
                        .font(.caption)
                        .foregroundStyle(Theme.Palette.warning)
                }
            }
            Section("Mitglied") {
                TextField("Vorname", text: bindingFor(\.firstName, on: draft))
                TextField("Nachname", text: bindingFor(\.lastName, on: draft))
                TextField("Titel", text: bindingFor(\.title, on: draft))
                Picker("Geschlecht", selection: bindingFor(\.gender, on: draft)) {
                    Text("–").tag("")
                    Text("weiblich").tag("f")
                    Text("männlich").tag("m")
                }
                OptionalDatePicker(label: "Geburtsdatum", date: bindingFor(\.birthDate, on: draft))
                TextField("Straße", text: bindingFor(\.street, on: draft))
                TextField("PLZ", text: bindingFor(\.zip, on: draft))
                    .keyboardType(.numberPad)
                TextField("Ort", text: bindingFor(\.city, on: draft))
                TextField("Land", text: bindingFor(\.country, on: draft))
            }
            Section("Kontakt") {
                TextField("E-Mail", text: bindingFor(\.email, on: draft))
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Telefon", text: bindingFor(\.phone, on: draft))
                    .keyboardType(.phonePad)
            }
            // Same fields/validation as MemberDetailView's "Mitgliedschaft"
            // section, minus the admin-assigned ones (see MemberChangeRequest's
            // doc comment) — kept as its own section rather than folded into
            // "Kontakt" since these are federation/payout data, not everyday
            // contact info.
            Section("Sportverband & Zahlungsdaten") {
                TextField("Sport-ID", text: bindingFor(\.sportId, on: draft))
                TextField("SVNR", text: bindingFor(\.svnr, on: draft))
                if !Validation.isPlausibleAustrianSVNR(draft.svnr) {
                    Label("SVNR-Format ungewöhnlich", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(Theme.Palette.warning)
                }
                TextField("IBAN", text: bindingFor(\.iban, on: draft))
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                if !Validation.ibanChecksumIsValid(draft.iban) {
                    Label("IBAN-Prüfsumme ungültig", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(Theme.Palette.warning)
                }
                OptionalDatePicker(label: "Letzte sportärztl. Untersuchung", date: bindingFor(\.lastMedicalExamination, on: draft))
            }
        }
    }

    /// `draft` is a plain `let` (not `@Bindable`), deliberately — it can be
    /// EITHER a brand-new, not-yet-inserted `MemberChangeRequest`
    /// (`.snapshot(of:)`) or an existing pending one already in the model
    /// context; `@Bindable` on a value that might not be tracked by SwiftUI
    /// yet risks losing edits on the not-yet-inserted path. A manual
    /// `Binding` over the reference type's `var` works identically either way.
    private func bindingFor<Value>(_ keyPath: ReferenceWritableKeyPath<MemberChangeRequest, Value>, on draft: MemberChangeRequest) -> Binding<Value> {
        Binding(get: { draft[keyPath: keyPath] }, set: { draft[keyPath: keyPath] = $0 })
    }

    private func submitIfChanged() {
        guard let draft, draft.differs(from: member) else { return }
        if draft.modelContext == nil {
            modelContext.insert(draft)
        }
        draft.requestedAt = .now
        MemberChangeRequestService.save(draft, modelContext: modelContext)
    }
}
