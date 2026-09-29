import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// The club's member roster, pushed from `VereinView`'s admin hub (see
/// MainTabView) as "Benutzerverwaltung" — its original standalone-tab name,
/// restored per user request 2026-09-12 (was briefly relabeled "Mitglieder"
/// after the tab merge). Self-wraps a NavigationStack + "Fertig" button
/// because it doubled as a sheet. New app accounts are auto-flagged
/// as club members by matching against this roster (see
/// Member.checkMembership in Models.swift). `Member.memberOfGVSC` makes
/// club membership an explicit per-entry flag rather than something implied
/// by mere presence on the roster, since this list also carries
/// helpers/coaches who aren't necessarily formal members. Account/role
/// administration (`UserListView`) and the role-change audit log
/// (`RoleChangeLogView`) are now siblings under the same hub rather than
/// toolbar buttons here.
struct MembersListView: View {
    let currentUser: User
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\Member.lastName), SortDescriptor(\Member.firstName)])
    private var members: [Member]
    @Query private var users: [User]
    @State private var showAdd = false
    // Two-step delete: swipe fills this, the confirmationDialog commits it.
    @State private var pendingDeletion: [Member] = []
    // Eagerly (re)generated whenever the roster changes, mirroring the
    // ShareLink pattern established for TeilnehmerlisteExport (see
    // MemberListView/cerebrum.md) — this user relies on VoiceOver, and a
    // hand-rolled "generate on tap, then show a share sheet" flow is the
    // specific pattern that previously froze the app under VoiceOver.
    // ShareLink itself, pointed at an already-ready file, is the safe path.
    @State private var exportURL: URL?
    @State private var showImporter = false
    @State private var importResultMessage: String?
    // Roster edits are one of audit.md's two explicitly-prioritized areas
    // for visible save/sync failure signaling (alongside role changes, see
    // UserListView) — see ServiceFailureSignal.swift.
    private let failureSignal = ServiceFailureSignal.shared

    // Extracted from `body` so the modifier chain on `List` stays short
    // enough for the type-checker (it timed out with these inline).
    private var deletionDialogShown: Binding<Bool> {
        Binding(get: { !pendingDeletion.isEmpty }, set: { if !$0 { pendingDeletion = [] } })
    }
    private var importAlertShown: Binding<Bool> {
        Binding(get: { importResultMessage != nil }, set: { if !$0 { importResultMessage = nil } })
    }
    private var failureAlertShown: Binding<Bool> {
        Binding(get: { failureSignal.message != nil }, set: { if !$0 { failureSignal.clear() } })
    }

    var body: some View {
        List {
            if members.isEmpty {
                ContentUnavailableView("Keine Mitglieder",
                                       systemImage: "building.columns",
                                       description: Text("Lege ein neues Mitglied an."))
            } else {
                ForEach(members) { member in
                    NavigationLink(value: AppRoute.member(member)) {
                        MemberRow(member: member, isLinked: hasMatchingAccount(member))
                    }
                }
                .onDelete { offsets in
                    pendingDeletion = offsets.map { members[$0] }
                }
            }
        }
        .navigationTitle("Benutzerverwaltung")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await SyncOrchestrationService.syncAll(modelContext: modelContext)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAdd = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Neues Mitglied")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showImporter = true } label: { Image(systemName: "square.and.arrow.down") }
                    .accessibilityLabel("Mitglieder importieren")
            }
            ToolbarItem(placement: .topBarTrailing) {
                if let exportURL {
                    ShareLink(item: exportURL) { Image(systemName: "square.and.arrow.up") }
                        .accessibilityLabel("Mitglieder exportieren")
                }
            }
        }
        .sheet(isPresented: $showAdd) {
            AddMemberView()
        }
        .confirmationDialog("Mitglied löschen?", isPresented: deletionDialogShown, titleVisibility: .visible) {
            Button("Löschen", role: .destructive) {
                deleteMembers(pendingDeletion)
                pendingDeletion = []
            }
            Button("Abbrechen", role: .cancel) { pendingDeletion = [] }
        } message: {
            Text("Der Eintrag wird aus der Vereinskartei entfernt. Team-Zuordnungen dieser Person werden ebenfalls gelöscht.")
        }
        .task(id: members.map(\.id)) {
            exportURL = try? MemberImportExport.exportFile(members: members)
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
            handleImport(result)
        }
        .alert("Import", isPresented: importAlertShown) {
            Button("OK") { importResultMessage = nil }
        } message: {
            Text(importResultMessage ?? "")
        }
        .alert("Fehler", isPresented: failureAlertShown) {
            Button("OK") { failureSignal.clear() }
        } message: {
            Text(failureSignal.message ?? "")
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let error):
            importResultMessage = "Import fehlgeschlagen: \(error.localizedDescription)"
        case .success(let url):
            let didAccess = url.startAccessingSecurityScopedResource()
            defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                let outcome = MemberImportExport.importMembers(from: data, into: members, modelContext: modelContext)
                importResultMessage = outcome.summary
            } catch {
                importResultMessage = "Datei konnte nicht gelesen werden: \(error.localizedDescription)"
            }
        }
    }

    private func hasMatchingAccount(_ member: Member) -> Bool {
        users.contains { Member.matches(email: $0.email, firstName: $0.firstName, lastName: $0.lastName, in: [member]) }
    }

    private func deleteMembers(_ toDelete: [Member]) {
        for member in toDelete {
            MemberService.delete(member, modelContext: modelContext)
        }
        // Re-fetched rather than using the `members` @Query array directly —
        // SwiftUI's @Query refresh isn't guaranteed to have landed yet at
        // this exact point, so a fresh fetch is the only way to be sure the
        // backup reflects the roster with these entries actually removed.
        let remaining = (try? modelContext.fetch(FetchDescriptor<Member>())) ?? []
        MemberBackup.snapshot(members: remaining)
    }
}
