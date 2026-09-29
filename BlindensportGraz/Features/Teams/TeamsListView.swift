import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct TeamsListView: View {
    let currentUser: User?
    @Environment(\.modelContext) private var modelContext
    // Intentionally unfiltered (audit.md SwiftData & CloudKit Finding 6):
    // this IS the club's full Teams list screen — at single-club scale
    // (Team.defaultTeams: 5 standing teams) every team belongs on it, no
    // subset would be correct here.
    @Query(sort: \Team.name) private var teams: [Team]
    @State private var showAdd = false
    // Eager-generation + ShareLink/.fileImporter, not a custom
    // generate-on-tap-then-sheet flow — see MembersListView's identical
    // pattern and cerebrum.md's VoiceOver share-sheet-freeze history.
    @State private var exportURL: URL?
    @State private var showImporter = false
    @State private var importResultMessage: String?

    var canManageTeams: Bool {
        guard let user = currentUser else { return false }
        return user.role == .admin || user.role == .coach
    }

    var body: some View {
        List {
            if teams.isEmpty {
                ContentUnavailableView("Keine Teams",
                                       systemImage: "person.3",
                                       description: Text("Lege ein neues Team an."))
            } else {
                ForEach(teams) { team in
                    NavigationLink(value: AppRoute.team(team)) {
                        TeamRow(team: team)
                    }
                }
                .onDelete(perform: deleteTeams)
            }
        }
        .navigationTitle("Teams")
        .refreshable {
            await SyncOrchestrationService.syncAll(modelContext: modelContext)
            await SyncOrchestrationService.ensureDefaultTeams(modelContext: modelContext)
        }
        .toolbar {
            if canManageTeams {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Neues Team")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showImporter = true } label: { Image(systemName: "square.and.arrow.down") }
                        .accessibilityLabel("Teams importieren")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if let exportURL {
                        ShareLink(item: exportURL) { Image(systemName: "square.and.arrow.up") }
                            .accessibilityLabel("Teams exportieren")
                    }
                }
            }
        }
        .sheet(isPresented: $showAdd) {
            AddTeamView()
        }
        .task(id: teams.map(\.id)) {
            exportURL = try? TeamImportExport.exportFile(teams: teams)
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
            handleImport(result)
        }
        .alert("Import", isPresented: Binding(
            get: { importResultMessage != nil },
            set: { if !$0 { importResultMessage = nil } }
        )) {
            Button("OK") { importResultMessage = nil }
        } message: {
            Text(importResultMessage ?? "")
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
                let outcome = TeamImportExport.importTeams(from: data, modelContext: modelContext)
                importResultMessage = outcome.summary
            } catch {
                importResultMessage = "Datei konnte nicht gelesen werden: \(error.localizedDescription)"
            }
        }
    }

    private func deleteTeams(at offsets: IndexSet) {
        if canManageTeams {
            for index in offsets {
                TeamService.delete(teams[index], modelContext: modelContext)
            }
        }
    }
}
