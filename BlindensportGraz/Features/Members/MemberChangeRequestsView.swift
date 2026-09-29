import SwiftUI
import SwiftData

/// Admin review queue for self-service "Vereinsdaten" edits — architecture-
/// review.md §5 P2. `RoleChangeLogView` is the layout precedent (pushed
/// from the Verein hub, no own NavigationStack).
struct MemberChangeRequestsView: View {
    let currentUser: User?
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MemberChangeRequest.requestedAt, order: .reverse) private var allRequests: [MemberChangeRequest]
    @Query private var members: [Member]
    @Query private var users: [User]

    private var pendingRequests: [MemberChangeRequest] {
        allRequests.filter { $0.status == MemberChangeRequest.pendingStatus }
    }

    private var decidedRequests: [MemberChangeRequest] {
        allRequests.filter { $0.status != MemberChangeRequest.pendingStatus }
    }

    private func member(for request: MemberChangeRequest) -> Member? {
        members.first { $0.id == request.memberID }
    }

    private func requesterName(_ requestedBy: String) -> String {
        guard let id = UUID(uuidString: requestedBy) else { return "?" }
        return users.first { $0.id == id }?.displayName ?? "?"
    }

    var body: some View {
        List {
            if pendingRequests.isEmpty && decidedRequests.isEmpty {
                ContentUnavailableView("Keine Änderungsanträge", systemImage: "person.crop.circle.badge.checkmark",
                                       description: Text("Selbst eingereichte Änderungen an Vereinsdaten erscheinen hier zur Prüfung."))
            } else {
                if !pendingRequests.isEmpty {
                    Section("Offen (\(pendingRequests.count))") {
                        ForEach(pendingRequests) { request in
                            NavigationLink {
                                MemberChangeRequestDetailView(request: request, member: member(for: request), currentUser: currentUser)
                            } label: {
                                row(for: request)
                            }
                        }
                    }
                }
                if !decidedRequests.isEmpty {
                    Section("Entschieden") {
                        ForEach(decidedRequests.prefix(50)) { request in
                            NavigationLink {
                                MemberChangeRequestDetailView(request: request, member: member(for: request), currentUser: currentUser)
                            } label: {
                                row(for: request)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Änderungsanträge")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await SyncOrchestrationService.syncAll(modelContext: modelContext)
        }
    }

    private func row(for request: MemberChangeRequest) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(member(for: request)?.fullName ?? "\(request.firstName) \(request.lastName)")
                Text("Beantragt von \(requesterName(request.requestedBy)) am \(request.requestedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if request.status != MemberChangeRequest.pendingStatus {
                Text(request.status == MemberChangeRequest.approvedStatus ? "Angenommen" : "Abgelehnt")
                    .font(.caption)
                    .foregroundStyle(request.status == MemberChangeRequest.approvedStatus ? .green : .secondary)
            }
        }
    }
}

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
                            VStack(alignment: .leading, spacing: 2) {
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
                        .foregroundStyle(.orange)
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
