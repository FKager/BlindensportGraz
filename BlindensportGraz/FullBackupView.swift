import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Admin-only whole-club export/restore screen — architecture-review.md §5
/// P2. Same eager-generation `ShareLink` + `.fileImporter` shape as
/// `TeamsListView`'s Teams import/export toolbar buttons, just as its own
/// screen rather than two toolbar icons, since a wrong tap here is far more
/// consequential (the whole club's data, not one team) and deserves an
/// explicit destination with its own explanation text.
struct FullBackupView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var exportURL: URL?
    @State private var exportError: String?
    @State private var showImporter = false
    @State private var restoreResultMessage: String?
    @State private var isRestoring = false

    var body: some View {
        Form {
            Section {
                Text("Sichert alle Vereinsdaten (Teams, Mitglieder, App-Konten, Veranstaltungen, Anwesenheiten u. a.) als JSON-Datei. Fotos und Belege sind aus Platzgründen nicht enthalten.")
                    .foregroundStyle(.secondary)
            }

            Section("Sichern") {
                if let exportURL {
                    ShareLink(item: exportURL) {
                        Label("Sicherung exportieren", systemImage: "square.and.arrow.up")
                    }
                } else if let exportError {
                    Label(exportError, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                } else {
                    ProgressView()
                }
            }

            Section("Wiederherstellen") {
                Text("Erstellt nur fehlende Datensätze aus einer Sicherungsdatei — bestehende Daten werden nie überschrieben. Gedacht für Notfälle (z. B. Datenverlust) oder Migrationen.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button {
                    showImporter = true
                } label: {
                    if isRestoring {
                        ProgressView()
                    } else {
                        Label("Sicherung einspielen", systemImage: "square.and.arrow.down")
                    }
                }
                .disabled(isRestoring)
            }
        }
        .navigationTitle("Datensicherung")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            regenerateExport()
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
            handleImport(result)
        }
        .alert("Wiederherstellung", isPresented: Binding(
            get: { restoreResultMessage != nil },
            set: { if !$0 { restoreResultMessage = nil } }
        )) {
            Button("OK") { restoreResultMessage = nil }
        } message: {
            Text(restoreResultMessage ?? "")
        }
    }

    private func regenerateExport() {
        do {
            exportURL = try FullBackup.export(modelContext: modelContext)
        } catch {
            exportError = "Export fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let error):
            restoreResultMessage = "Import fehlgeschlagen: \(error.localizedDescription)"
        case .success(let url):
            isRestoring = true
            let didAccess = url.startAccessingSecurityScopedResource()
            defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                let outcome = try FullBackupImporter.restore(from: data, modelContext: modelContext)
                restoreResultMessage = summary(for: outcome)
                regenerateExport() // the restored data changed the store, refresh the export snapshot
            } catch {
                restoreResultMessage = "Datei konnte nicht gelesen werden: \(error.localizedDescription)"
            }
            isRestoring = false
        }
    }

    private func summary(for result: FullBackupImporter.Result) -> String {
        if result.totalCreated == 0 && result.totalSkipped == 0 {
            return "Die Sicherungsdatei enthielt keine Datensätze."
        }
        var lines = ["\(result.totalCreated) Datensätze neu angelegt."]
        if result.totalSkipped > 0 {
            lines.append("\(result.totalSkipped) bereits vorhanden oder übersprungen.")
        }
        return lines.joined(separator: " ")
    }
}
