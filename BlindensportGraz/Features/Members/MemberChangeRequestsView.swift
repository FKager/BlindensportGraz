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
                            NavigationLink(value: AppRoute.memberChangeRequest(request, member: member(for: request))) {
                                row(for: request)
                            }
                        }
                    }
                }
                if !decidedRequests.isEmpty {
                    Section("Entschieden") {
                        ForEach(decidedRequests.prefix(50)) { request in
                            NavigationLink(value: AppRoute.memberChangeRequest(request, member: member(for: request))) {
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
