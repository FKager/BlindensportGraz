import SwiftUI
import SwiftData

/// Admin-only screen (see TrainingsListView's "Berichte" toolbar menu) that
/// bundles a WHOLE calendar year's paperwork — every month's and every
/// tournament's Sammelabrechnung, plus every training sport's two
/// Trainingsfrequenzliste half-years — into one .zip (audit.md Enhancement
/// #8, `SammelabrechnungExporter.exportSeason`'s doc comment). Same
/// eager-export-via-`.task`-then-`ShareLink` pattern as every other export
/// screen in this app.
struct SammelabrechnungSeasonView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    // Intentionally unfiltered — see SammelabrechnungView's identical
    // @Query comment above.
    @Query private var allMemberships: [TeamMembership]
    // No query-level `sort:` — `startDate` is inherited from SportEvent and
    // SwiftData traps on an inherited-property sort key path in Release
    // builds (bug-352). `exportSeason` sorts tournaments itself; `trainings`
    // here only feeds a Set of sport names, so order is irrelevant.
    @Query private var tournaments: [Tournament]
    @Query private var trainings: [Training]

    @State private var year = Calendar.current.component(.year, from: .now)
    @State private var exportURL: URL?
    @State private var exportError: String?

    // Same "distinct sports across every training ever created" source as
    // TrainingsfrequenzlisteView's availableSports.
    private var sports: [String] {
        Array(Set(trainings.map(\.sport))).sorted()
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Zeitraum") {
                    Stepper("Jahr: \(String(year))", value: $year, in: 2020...2100)
                }

                Section("Export") {
                    Text("Bündelt alle Monats- und Turnier-Sammelabrechnungen sowie alle Trainingsfrequenzlisten dieses Jahres als eine ZIP-Datei.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let exportURL {
                        ShareLink(item: exportURL) {
                            Label("Saison-Sammelabrechnung exportieren", systemImage: "doc.zipper")
                        }
                    } else {
                        Label("Saison-Sammelabrechnung wird vorbereitet …", systemImage: "doc.zipper")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Saison-Sammelabrechnung")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
            .alert("Export fehlgeschlagen", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(exportError ?? "")
            }
            .task(id: year) {
                exportURL = nil
                do {
                    exportURL = try SammelabrechnungExporter.exportSeason(
                        year: year, allMemberships: allMemberships, tournaments: tournaments,
                        sports: sports, in: modelContext)
                } catch {
                    exportError = error.localizedDescription
                }
            }
        }
    }
}
