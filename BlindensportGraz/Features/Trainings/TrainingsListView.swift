import SwiftUI
import SwiftData
import Combine
import UniformTypeIdentifiers

struct TrainingsListView: View {
     let currentUser: User?
        @Environment(\.modelContext) private var modelContext
        // No query-level `sort:` — `startDate` is inherited from SportEvent and
        // SwiftData traps on an inherited-property sort key path in Release
        // builds (bug-352). Sort newest-first in memory via sortedTrainings.
        @Query private var trainings: [Training]
        @State private var showAdd = false
        @State private var showAttendanceTrends = false
        @State private var showSeasonDashboard = false
        @State private var showTrainingsfrequenzliste = false
        @State private var showPraeCalculation = false
        @State private var showKostZCalculation = false
        @State private var showSammelabrechnung = false
        @State private var showSammelabrechnungSeason = false
        // Same eager-generation + ShareLink convention as MembersListView's
        // import/export (see that view's doc comment) — a hand-rolled
        // "generate on tap" flow previously froze the app under VoiceOver.
        @State private var exportURL: URL?
        @State private var showImporter = false
        @State private var importResultMessage: String?
        // Filter option (user request 2026-09-16): "filtering option for
        // month and type, default all entries listed". nil means unfiltered
        // — both default to nil so the list shows everything until the user
        // picks something, matching "as default all entries should be
        // listed."
        @State private var selectedMonth: Int?
        @State private var selectedSport: String?

    var canManageEvents: Bool {
        guard let user = currentUser else { return false }
        return user.role == .admin || user.role == .coach
       }

    // Matches the gating the Trainingsfrequenzliste button used in AccountView
    // before it moved here (see TrainingsfrequenzlisteView's doc comment).
    var isAdmin: Bool {
        currentUser?.role == .admin || (currentUser?.isRoot ?? false)
       }

    // Newest-first, matching the old @Query(order: .reverse).
    var sortedTrainings: [Training] {
        trainings.sorted { $0.startDate > $1.startDate }
    }

    var visibleTrainings: [Training] {
        if currentUser?.role == .admin { return sortedTrainings }
        let myTeamIDs = Set(currentUser?.memberships.map { $0.team.id } ?? [])
        return sortedTrainings.filter { $0.teams.isEmpty || $0.teams.contains(where: { myTeamIDs.contains($0.id) }) }
    }

    // Sportart choices for the "Sportart"-filter Picker — only sports that
    // actually occur among visibleTrainings, not the fixed AddTrainingView
    // list, so the picker never offers a sport nothing is filed under (and
    // still surfaces free-text sports per Sport.swift's design).
    var availableSports: [String] {
        Array(Set(visibleTrainings.map(\.sport))).sorted()
    }

    var filteredTrainings: [Training] {
        var result = visibleTrainings
        if let selectedMonth {
            let calendar = Calendar.current
            result = result.filter { calendar.component(.month, from: $0.startDate) == selectedMonth }
        }
        if let selectedSport {
            result = result.filter { $0.sport == selectedSport }
        }
        return result
    }

    private func monthName(_ month: Int) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_AT")
        return formatter.monthSymbols[month - 1].capitalized
    }

    var body: some View {
        List {
           Section {
               Picker("Monat", selection: $selectedMonth) {
                   Text("Alle Monate").tag(nil as Int?)
                   ForEach(1...12, id: \.self) { m in
                       Text(monthName(m)).tag(m as Int?)
                   }
               }
               .pickerStyle(.menu)
               Picker("Sportart", selection: $selectedSport) {
                   Text("Alle Sportarten").tag(nil as String?)
                   ForEach(availableSports, id: \.self) { sport in
                       Text(sport).tag(sport as String?)
                   }
               }
               .pickerStyle(.menu)
           }
           if filteredTrainings.isEmpty {
               ContentUnavailableView("Keine Trainings",
                                      systemImage: "figure.run",
                                      description: Text("Lege ein neues Training an."))
              } else {
                  ForEach(filteredTrainings) { training in
                    NavigationLink(value: AppRoute.training(training)) {
                           TrainingRow(training: training)
                         }
                       .swipeActions(edge: .trailing) {
                           Button(role: .destructive) {
                               delete(training)
                           } label: {
                               Label("Löschen", systemImage: "trash")
                           }
                           if training.status != Training.cancelledStatus {
                               Button {
                                   markCancelled(training)
                               } label: {
                                   Label("Abgesagt", systemImage: "xmark.circle")
                               }
                               .tint(.orange)
                           }
                       }
                       }
                      }
                 }
        .navigationTitle("Trainings")
        .refreshable {
            await SyncOrchestrationService.syncAll(modelContext: modelContext)
        }
        .toolbar {
            // Gated to admin/coach via canManageEvents (Phase 7's AppRole
            // enum, not a raw string) rather than isAdmin — coaches should
            // see their own teams' attendance trends too, unlike the
            // finance-report items below this one which stay admin-only.
            if canManageEvents {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAttendanceTrends = true } label: {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                    }
                    .accessibilityLabel("Anwesenheitstrends")
                }
            }
            if isAdmin {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { showSeasonDashboard = true } label: {
                            Label("Saison-Übersicht", systemImage: "chart.bar.xaxis")
                        }
                        Button { showTrainingsfrequenzliste = true } label: {
                            Label("Trainingsfrequenzliste", systemImage: "calendar.badge.checkmark")
                        }
                        Button { showPraeCalculation = true } label: {
                            Label("PRAE-Berechnung", systemImage: "eurosign.circle.fill")
                        }
                        Button { showKostZCalculation = true } label: {
                            Label("KostZ-Berechnung", systemImage: "doc.text.fill")
                        }
                        Button { showSammelabrechnung = true } label: {
                            Label("Sammelabrechnung", systemImage: "doc.zipper")
                        }
                        Button { showSammelabrechnungSeason = true } label: {
                            Label("Saison-Sammelabrechnung", systemImage: "doc.zipper.fill")
                        }
                    } label: {
                        Image(systemName: "chart.bar.doc.horizontal")
                    }
                    .accessibilityLabel("Berichte")
                }
            }
            if canManageEvents {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showImporter = true } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                    .accessibilityLabel("Trainings importieren")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if let exportURL {
                        ShareLink(item: exportURL) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel("Trainings exportieren")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Neues Training")
                }
            }
        }
        .sheet(isPresented: $showAdd) {
            AddTrainingView(currentUser: currentUser)
        }
        .sheet(isPresented: $showAttendanceTrends) {
            AttendanceTrendsView()
        }
        .sheet(isPresented: $showSeasonDashboard) {
            SeasonDashboardView()
        }
        .sheet(isPresented: $showTrainingsfrequenzliste) {
            TrainingsfrequenzlisteView()
        }
        .sheet(isPresented: $showPraeCalculation) {
            PraeCalculationView()
        }
        .sheet(isPresented: $showKostZCalculation) {
            KostZCalculationView(currentUser: currentUser)
        }
        .sheet(isPresented: $showSammelabrechnung) {
            SammelabrechnungView()
        }
        .sheet(isPresented: $showSammelabrechnungSeason) {
            SammelabrechnungSeasonView()
        }
        .task(id: trainings.map(\.id)) {
            exportURL = try? TrainingImportExport.exportFile(trainings: sortedTrainings)
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
                let outcome = TrainingImportExport.importTrainings(from: data, into: trainings, modelContext: modelContext)
                importResultMessage = outcome.summary
            } catch {
                importResultMessage = "Datei konnte nicht gelesen werden: \(error.localizedDescription)"
            }
        }
    }

    // Routed through TrainingService.delete (phase 14) so the local
    // reminder — see EventReminderService — gets cancelled; still no
    // CloudKit delete push, that scoping is unchanged (no CloudKit delete
    // path exists for Training records, see EventsListView.deleteEvents'
    // identical comment). Swipe-to-delete replaced the old `.onDelete`
    // modifier (user request 2026-09-10: "Abgesagt und Löschen als
    // Swipe-Option") so this now takes the single row's model directly
    // instead of an IndexSet into visibleTrainings.
    private func delete(_ training: Training) {
        modelContext.delete(training)
        TrainingService.delete(training, modelContext: modelContext)
    }

    // The other swipe action: marks a training cancelled (without deleting
    // the training itself — that's the "Löschen" action above). Plain field
    // mutation + the standard save/push, same as any other in-place edit in
    // this app.
    private func markCancelled(_ training: Training) {
        training.status = Training.cancelledStatus
        TrainingService.save(training, modelContext: modelContext)
        // A cancelled training never happened, so its attendance is deleted
        // outright, not just reset (user request 2026-09-10) — see
        // AttendanceService.deleteAll's doc comment.
        AttendanceService.deleteAll(for: training, modelContext: modelContext)
    }
}
