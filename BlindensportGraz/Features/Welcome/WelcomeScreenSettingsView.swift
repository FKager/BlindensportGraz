import SwiftUI
import SwiftData

/// Admin settings screen (pushed from `VereinHubList`/`VereinSplitView`)
/// showing whether this device can see `welcome.md` in its own iCloud Drive,
/// a manual re-sync button, the shared on/off toggle, and a preview — all
/// backed by the CloudKit-synced `WelcomeContent` singleton, not any
/// per-device state.
struct WelcomeScreenSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var content: WelcomeContent?
    @State private var localFileFound = false
    @State private var showPreview = false

    var body: some View {
        Form {
            Section {
                if localFileFound {
                    Label("welcome.md auf diesem Gerät gefunden", systemImage: "checkmark.icloud.fill")
                        .foregroundStyle(.green)
                } else {
                    Label("Keine welcome.md in der iCloud Drive dieses Geräts gefunden", systemImage: "xmark.icloud")
                        .foregroundStyle(.secondary)
                }
                Button {
                    syncNow()
                } label: {
                    Label("Jetzt synchronisieren", systemImage: "arrow.triangle.2.circlepath")
                }
            } header: {
                Text("iCloud-Datei")
            } footer: {
                Text("Lege welcome.md in \"iCloud Drive/Blindensport Graz\" ab (Dateien-App oder Finder). Von hier aus wird der Inhalt mit allen Mitgliedern geteilt — ein anderes Gerät zeigt die Datei selbst nicht an, nur den bereits geteilten Text unten.")
            }

            if let content {
                Section {
                    WelcomeEnabledToggle(content: content)
                    if !content.markdown.isEmpty {
                        Button {
                            showPreview = true
                        } label: {
                            Label("Vorschau", systemImage: "eye")
                        }
                        LabeledContent("Zuletzt aktualisiert",
                                       value: content.updatedAt.formatted(date: .abbreviated, time: .shortened))
                    }
                }
            }
        }
        .navigationTitle("Willkommensbildschirm")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            content = WelcomeContent.current(in: modelContext)
            localFileFound = WelcomeFileWatcher.fileExistsOnThisDevice
        }
        .fullScreenCover(isPresented: $showPreview) {
            if let content {
                WelcomeView(markdown: content.markdown) { showPreview = false }
            }
        }
    }

    private func syncNow() {
        localFileFound = WelcomeFileWatcher.fileExistsOnThisDevice
        guard let localMarkdown = WelcomeFileWatcher.readLocalFile() else { return }
        let updated = WelcomeContent.fetchOrCreate(in: modelContext)
        updated.markdown = localMarkdown
        updated.isEnabled = true
        WelcomeContentService.save(updated, modelContext: modelContext)
        content = updated
    }
}
