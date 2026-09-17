import SwiftUI
import SwiftData

/// Watches this app's own iCloud Drive "Documents" folder (visible in the
/// Files app / Finder as "Blindensport Graz" once `NSUbiquitousContainers`/
/// `CloudDocuments` are enabled — see Info.plist/entitlements) for a
/// `welcome.md` file. This is the authoring source: an admin edits that file
/// directly (Mac Finder, iOS Files app, ...). It's read-only per device
/// (never written by the app) and, critically, private to whichever Apple ID
/// owns that iCloud Drive — it does NOT sync across different users'
/// accounts the way CloudKit's public database does. `RootView` bridges the
/// two: on whichever admin device can actually see this file, it pushes the
/// file's content into the shared `WelcomeContent` CloudKit record
/// (`CloudKitSync+WelcomeContent.swift`), and every other user's device just
/// displays that already-synced record. This replaces an earlier
/// per-device security-scoped-bookmark design that only ever worked on the
/// one device that picked the file.
enum WelcomeFileWatcher {
    static let fileName = "welcome.md"

    /// `Documents/welcome.md` inside this app's own ubiquity container, or
    /// `nil` if iCloud Drive isn't available on this device (iCloud
    /// disabled, container not yet provisioned, etc.).
    static var fileURL: URL? {
        FileManager.default.url(forUbiquityContainerIdentifier: "iCloud.it.a11y.BlindensportGraz")?
            .appendingPathComponent("Documents")
            .appendingPathComponent(fileName)
    }

    static var fileExistsOnThisDevice: Bool {
        guard let fileURL else { return false }
        return FileManager.default.fileExists(atPath: fileURL.path)
    }

    /// Reads `welcome.md` if this device's iCloud Drive has it, kicking off
    /// a download first if iCloud hasn't materialized it locally yet.
    /// Returns `nil` on every device except whichever one the admin actually
    /// edits the file on — that's the expected, normal case, not an error.
    static func readLocalFile() -> String? {
        guard let url = fileURL, FileManager.default.fileExists(atPath: url.path) else { return nil }

        if let values = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]),
           values.ubiquitousItemDownloadingStatus != .current {
            try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        }

        var content: String?
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { readURL in
            content = try? String(contentsOf: readURL, encoding: .utf8)
        }
        return content
    }
}

/// Minimal line-based Markdown renderer for the welcome screen's content —
/// headers, bullet/numbered lists and inline emphasis/links (via
/// `AttributedString(markdown:)`) per line. Deliberately not a full
/// CommonMark implementation (nested lists, tables, code blocks) — this only
/// needs to render a short welcome note.
struct MarkdownContentView: View {
    let markdown: String

    private var lines: [String] {
        markdown.components(separatedBy: .newlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                blockView(for: line)
            }
        }
    }

    @ViewBuilder
    private func blockView(for rawLine: String) -> some View {
        let line = rawLine.trimmingCharacters(in: .whitespaces)
        if line.isEmpty {
            Spacer().frame(height: 4)
        } else if line.hasPrefix("### ") {
            inlineText(String(line.dropFirst(4))).font(.title3.bold())
        } else if line.hasPrefix("## ") {
            inlineText(String(line.dropFirst(3))).font(.title2.bold())
        } else if line.hasPrefix("# ") {
            inlineText(String(line.dropFirst(2))).font(.largeTitle.bold())
        } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
            HStack(alignment: .top, spacing: 8) {
                Text("•")
                inlineText(String(line.dropFirst(2)))
            }
        } else if let dotRange = line.range(of: ". "),
                  !line[..<dotRange.lowerBound].isEmpty,
                  line[..<dotRange.lowerBound].allSatisfy(\.isNumber) {
            HStack(alignment: .top, spacing: 8) {
                Text(String(line[..<dotRange.upperBound]))
                inlineText(String(line[dotRange.upperBound...]))
            }
        } else {
            inlineText(line).font(.body)
        }
    }

    private func inlineText(_ text: String) -> Text {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        if let attributed = try? AttributedString(markdown: text, options: options) {
            return Text(attributed)
        }
        return Text(text)
    }
}

/// Full-screen welcome note shown by `RootView` on launch (when enabled and
/// non-empty) and reused by `WelcomeScreenSettingsView`'s preview.
struct WelcomeView: View {
    let markdown: String
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Image(systemName: "hand.wave.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(
                            LinearGradient(colors: [.blue, .purple],
                                           startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(maxWidth: .infinity)

                    MarkdownContentView(markdown: markdown)
                }
                .padding()
            }
            .navigationTitle("Willkommen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Weiter") { onDismiss() }
                }
            }
        }
    }
}

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
                    Toggle("Für alle Mitglieder anzeigen", isOn: Binding(
                        get: { content.isEnabled },
                        set: { newValue in
                            content.isEnabled = newValue
                            WelcomeContentService.save(content, modelContext: modelContext)
                        }
                    ))
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
