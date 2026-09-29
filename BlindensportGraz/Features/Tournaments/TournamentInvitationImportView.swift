import SwiftUI
import SwiftData
import Combine

/// "Turnier aus Einladung erstellen" (user request) — lets an admin/coach
/// upload an invitation (.txt/.docx/.pdf) and have `AddTournamentView` open
/// prefilled from it instead of blank. See `TournamentInvitationImporter`
/// for the actual text/field extraction; this view is just the file picker
/// + progress/error UI around it.
///
/// Once a draft is extracted, this view's own body simply BECOMES
/// `AddTournamentView(currentUser:draft:)` — not a second, separately
/// presented sheet stacked on top of this one, which would risk the classic
/// SwiftUI "dismiss one sheet and present another in the same tick" timing
/// glitch. Since it's inline content of the sheet this view itself already
/// is, `AddTournamentView`'s own "Speichern"/"Abbrechen" (which call
/// `dismiss()`) close this whole sheet exactly the same way they would if
/// presented directly from TournamentsListView.
struct TournamentInvitationImportView: View {
    let currentUser: User?
    // Set when this view was opened by sharing a file into the app via the
    // system share sheet (BlindensportGrazShareExtension +
    // ShareExtensionBridge — user request), rather than the in-app "Datei
    // auswählen" button below. When set, processing starts immediately
    // instead of waiting for a tap, and the file is cleaned out of the
    // shared App Group container once this view is done with it (one-shot
    // hand-off, not a durable inbox — see ShareExtensionBridge.cleanup).
    var sharedFileURL: URL? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var showFileImporter = false
    @State private var isProcessing = false
    @State private var draft: TournamentDraft?
    @State private var errorMessage: String?
    @State private var didStartSharedImport = false

    var body: some View {
        if let draft {
            AddTournamentView(currentUser: currentUser, draft: draft)
        } else {
            NavigationStack {
                VStack(spacing: 20) {
                    Spacer()
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundStyle(.blue)
                        .accessibilityHidden(true)
                    Text("Turnier aus Einladung erstellen")
                        .font(.title3.bold())
                    Text("Wähle eine Einladung als Text-, Word- (.docx) oder PDF-Datei. Titel, Sportart, Ort und Zeitraum werden automatisch ausgefüllt und können danach noch angepasst werden.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    if isProcessing {
                        ProgressView("Analysiere Einladung …")
                            .padding(.top)
                    } else {
                        Button {
                            showFileImporter = true
                        } label: {
                            Label("Datei auswählen", systemImage: "doc.badge.plus")
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.top)
                    }
                    Spacer()
                }
                .padding()
                .navigationTitle("Aus Einladung")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Abbrechen") { dismiss() }
                    }
                }
                .fileImporter(
                    isPresented: $showFileImporter,
                    allowedContentTypes: TournamentInvitationImporter.supportedContentTypes
                ) { result in
                    switch result {
                    case .failure(let error):
                        errorMessage = error.localizedDescription
                    case .success(let url):
                        process(url)
                    }
                }
                .alert("Import fehlgeschlagen", isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )) {
                    Button("OK") { errorMessage = nil }
                } message: {
                    Text(errorMessage ?? "")
                }
                .task {
                    guard let sharedFileURL, !didStartSharedImport else { return }
                    didStartSharedImport = true
                    process(sharedFileURL)
                }
            }
        }
    }

    private func process(_ url: URL) {
        isProcessing = true
        Task {
            do {
                let extracted = try await TournamentInvitationImporter.draft(fromFileAt: url)
                if url == sharedFileURL { ShareExtensionBridge.cleanup(url) }
                isProcessing = false
                draft = extracted
            } catch {
                if url == sharedFileURL { ShareExtensionBridge.cleanup(url) }
                isProcessing = false
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}
