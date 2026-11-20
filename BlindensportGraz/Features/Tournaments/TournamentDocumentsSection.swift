import SwiftUI
import SwiftData
import QuickLook

/// "Dokumente" of a tournament (invitation, schedule, results …): every
/// approved account opens them (Quick Look); events.manage adds several at
/// once and deletes them. Shown in TournamentDetailView in both the
/// read-only and the editing mode.
struct TournamentDocumentsSection: View {
    let tournament: Tournament
    let currentUser: User?
    @Environment(\.modelContext) private var modelContext
    @Query private var allDocuments: [TournamentInvitation]

    @State private var showImporter = false
    @State private var previewURL: URL?
    @State private var pendingDelete: TournamentInvitation?
    @State private var errorMessage: String?

    private var documents: [TournamentInvitation] {
        TournamentInvitationService.documents(for: tournament, in: allDocuments)
    }

    private var canManage: Bool {
        currentUser?.can(.eventsManage) ?? false
    }

    var body: some View {
        if canManage || !documents.isEmpty {
            Section {
                ForEach(documents) { document in
                    Button { open(document) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(document.fileName.isEmpty ? "Dokument" : document.fileName)
                                .foregroundStyle(.primary)
                            Text(detail(for: document))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityHint("Öffnet das Dokument")
                    .swipeActions {
                        if canManage {
                            Button(role: .destructive) { pendingDelete = document } label: {
                                Label("Löschen", systemImage: "trash")
                            }
                        }
                    }
                    .contextMenu {
                        if canManage {
                            Button(role: .destructive) { pendingDelete = document } label: {
                                Label("Löschen", systemImage: "trash")
                            }
                        }
                    }
                }
                if canManage {
                    Button { showImporter = true } label: {
                        Label("Dokumente hinzufügen", systemImage: "doc.badge.plus")
                    }
                }
            } header: {
                Text("Dokumente (\(documents.count))")
            } footer: {
                if canManage {
                    Text("Zum Beispiel Einladung, Spielplan oder Ergebnisse — PDF, Word, Excel, Text oder Bild, bis 15 MB. Für alle freigeschalteten Mitglieder sichtbar.")
                }
            }
            .fileImporter(isPresented: $showImporter,
                          allowedContentTypes: TournamentInvitation.supportedContentTypes,
                          allowsMultipleSelection: true,
                          onCompletion: add)
            .quickLookPreview($previewURL)
            .confirmationDialog("Dokument „\(pendingDelete?.fileName ?? "")“ löschen?",
                                isPresented: Binding(isPresent: $pendingDelete),
                                titleVisibility: .visible) {
                Button("Löschen", role: .destructive) {
                    if let pendingDelete {
                        TournamentInvitationService.delete(pendingDelete, modelContext: modelContext)
                    }
                    pendingDelete = nil
                }
            }
            .alert("Dokument", isPresented: Binding(isPresent: $errorMessage)) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func detail(for document: TournamentInvitation) -> String {
        let size = ByteCountFormatter.string(fromByteCount: Int64(document.fileData.count), countStyle: .file)
        return "\(document.fileExtension.uppercased()), \(size), \(document.uploadedAt.formatted(date: .abbreviated, time: .omitted))"
    }

    private func open(_ document: TournamentInvitation) {
        do {
            previewURL = try Self.temporaryFile(for: document)
        } catch {
            errorMessage = "Das Dokument konnte nicht geöffnet werden: \(error.localizedDescription)"
        }
    }

    private func add(_ result: Result<[URL], Error>) {
        let urls: [URL]
        do {
            urls = try result.get()
        } catch {
            errorMessage = "Die Dokumente konnten nicht geladen werden: \(error.localizedDescription)"
            return
        }
        var problems: [String] = []
        for url in urls {
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            let name = url.lastPathComponent
            guard TournamentInvitation.isSupported(fileName: name) else {
                problems.append("\(name): Dateityp wird nicht unterstützt.")
                continue
            }
            guard let data = try? Data(contentsOf: url) else {
                problems.append("\(name): konnte nicht gelesen werden.")
                continue
            }
            guard data.count <= TournamentInvitation.maxFileSize else {
                problems.append("\(name): größer als 15 MB.")
                continue
            }
            TournamentInvitationService.add(to: tournament, data: data, fileName: name,
                                            uploadedBy: currentUser?.id.uuidString ?? "",
                                            modelContext: modelContext)
        }
        if !problems.isEmpty {
            errorMessage = problems.joined(separator: "\n")
        }
    }

    /// The document as a file under its own name (Quick Look needs a URL and
    /// shows the name), in a fresh temp folder so equal names never collide.
    static func temporaryFile(for document: TournamentInvitation) throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent(document.id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = document.fileName.replacingOccurrences(of: "/", with: "-")
        let url = folder.appendingPathComponent(name.isEmpty ? "Dokument.\(document.fileExtension)" : name)
        try document.fileData.write(to: url, options: .atomic)
        return url
    }
}
