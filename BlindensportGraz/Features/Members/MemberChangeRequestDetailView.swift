import SwiftUI
import SwiftData

/// One request's proposed fields vs. the member's current values, with an
/// Annehmen/Ablehnen decision — only shown while `request` is still pending.
struct MemberChangeRequestDetailView: View {
    @Bindable var request: MemberChangeRequest
    let member: Member?
    let currentUser: User?
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    private struct FieldDiff: Identifiable {
        let id = UUID()
        let label: String
        let oldValue: String
        let newValue: String
    }

    private func diffs(against member: Member) -> [FieldDiff] {
        var out: [FieldDiff] = []
        func add(_ label: String, _ old: String, _ new: String) {
            guard old != new else { return }
            out.append(FieldDiff(label: label, oldValue: old.isEmpty ? "–" : old, newValue: new.isEmpty ? "–" : new))
        }
        add("Vorname", member.firstName, request.firstName)
        add("Nachname", member.lastName, request.lastName)
        add("Titel", member.title, request.title)
        add("Geschlecht", member.gender, request.gender)
        add("Geburtsdatum", dateString(member.birthDate), dateString(request.birthDate))
        add("Straße", member.street, request.street)
        add("PLZ", member.zip, request.zip)
        add("Ort", member.city, request.city)
        add("Land", member.country, request.country)
        add("E-Mail", member.email, request.email)
        add("Telefon", member.phone, request.phone)
        add("Sport-ID", member.sportId, request.sportId)
        add("SVNR", member.svnr, request.svnr)
        add("IBAN", member.iban, request.iban)
        add("Letzte sportärztl. Untersuchung", dateString(member.lastMedicalExamination), dateString(request.lastMedicalExamination))
        return out
    }

    private func dateString(_ date: Date?) -> String {
        date?.formatted(date: .abbreviated, time: .omitted) ?? ""
    }

    var body: some View {
        Form {
            if let member {
                Section("Änderungen") {
                    let changes = diffs(against: member)
                    if changes.isEmpty {
                        Text("Keine Unterschiede mehr zu den aktuellen Vereinsdaten.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(changes) { diff in
                            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                                Text(diff.label)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                HStack {
                                    Text(diff.oldValue)
                                        .strikethrough()
                                        .foregroundStyle(.secondary)
                                    Image(systemName: "arrow.right")
                                        .accessibilityHidden(true)
                                    Text(diff.newValue)
                                        .bold()
                                }
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("\(diff.label): von \(diff.oldValue) zu \(diff.newValue)")
                        }
                    }
                }
            } else {
                Section {
                    Label("Zugehöriges Mitglied nicht gefunden — vermutlich zwischenzeitlich gelöscht.",
                          systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Theme.Palette.warning)
                }
            }

            Section {
                LabeledContent("Beantragt am", value: request.requestedAt.formatted(date: .abbreviated, time: .shortened))
                if let reviewedAt = request.reviewedAt {
                    LabeledContent("Entschieden am", value: reviewedAt.formatted(date: .abbreviated, time: .shortened))
                }
            }

            if request.status == MemberChangeRequest.pendingStatus, let member {
                Section {
                    Button {
                        MemberChangeRequestService.approve(request, member: member,
                                                            reviewedBy: currentUser?.id.uuidString ?? "", modelContext: modelContext)
                        dismiss()
                    } label: {
                        Label("Annehmen", systemImage: "checkmark.circle.fill")
                    }
                    Button(role: .destructive) {
                        MemberChangeRequestService.reject(request, reviewedBy: currentUser?.id.uuidString ?? "", modelContext: modelContext)
                        dismiss()
                    } label: {
                        Label("Ablehnen", systemImage: "xmark.circle")
                    }
                }
            } else if request.status != MemberChangeRequest.pendingStatus {
                Section {
                    LabeledContent("Status", value: request.status == MemberChangeRequest.approvedStatus ? "Angenommen" : "Abgelehnt")
                }
            }
        }
        .navigationTitle(member?.fullName ?? "Änderungsantrag")
        .navigationBarTitleDisplayMode(.inline)
    }
}
