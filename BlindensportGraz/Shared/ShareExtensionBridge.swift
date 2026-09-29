import Foundation

/// Bridges a file shared into iOS's system share sheet ("Turnier aus
/// Einladung erstellen" via the `BlindensportGrazShareExtension` app
/// extension target — user request) from the extension process to the main
/// app.
///
/// Deliberately just a file copy through the same App Group container
/// `WidgetBridge` already uses for the home-screen widget (see that file's
/// doc comment for the underlying reasoning), which doubles as an inbox the
/// main app checks whenever it becomes active (`nextPendingFile()`), plus a
/// best-effort custom-URL-scheme hand-off that opens the app right away — NOT SwiftData/CloudKit access from inside the extension
/// itself. Share Extension processes are short-lived and memory-
/// constrained, and none of `TournamentInvitationImporter`'s work (Apple
/// Intelligence, PDFKit, ZIPFoundation, eventual SwiftData insert) is worth
/// duplicating or risking there — the extension's only job is: grab the
/// shared file, copy it somewhere the main app can reach, and bring the
/// main app to the foreground pointed at it. The main app does the actual
/// extraction/creation with its normal resources, through the exact same
/// `TournamentInvitationImportView` flow already used for the in-app
/// "Turnier aus Einladung erstellen" button.
///
/// Compiled into both the main app target and the share extension target
/// (see project.yml), same as `WidgetShared.swift` is for the widget
/// extension — they only ever meet as a file on disk in the shared
/// container, which is identical because the source is.
enum ShareExtensionBridge {
    /// Must match the App Group id registered on every target's
    /// entitlements (main app, widgets, this extension).
    static let appGroup = "group.it.a11y.BlindensportGraz"
    private static let subfolder = "SharedInvitations"
    static let urlScheme = "blindensportgraz"
    static let importHost = "import-invitation"

    private static var containerDirectory: URL? {
        guard let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) else {
            return nil
        }
        let dir = base.appendingPathComponent(subfolder, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Extension side: copies a shared file (from `NSItemProvider.
    /// loadFileRepresentation`'s callback — that URL is only valid for the
    /// duration of the callback, so this must run synchronously before it
    /// returns) into the App Group container under a fresh unique name,
    /// preserving the original extension since `TournamentInvitationImporter
    /// .extractText` dispatches on `url.pathExtension`. Returns the deep
    /// link the extension uses to open the main app, or nil if the App Group
    /// container or the copy itself failed. The copied file stays in the
    /// inbox either way, so the app finds it even if the deep link fails.
    static func store(fileAt sourceURL: URL) -> URL? {
        guard let dir = containerDirectory else { return nil }
        let destinationName = UUID().uuidString + "." + sourceURL.pathExtension
        let destinationURL = dir.appendingPathComponent(destinationName)
        do {
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        } catch {
            return nil
        }
        var components = URLComponents()
        components.scheme = urlScheme
        components.host = importHost
        components.queryItems = [URLQueryItem(name: "file", value: destinationName)]
        return components.url
    }

    /// App side: resolves an incoming `blindensportgraz://import-invitation
    /// ?file=...` deep link (see `RootView.onOpenURL`) back to the actual
    /// file inside the App Group container. Returns nil for any URL that
    /// isn't one of ours, or whose file no longer exists (already consumed,
    /// or the container was cleared).
    static func resolveIncoming(_ url: URL) -> URL? {
        guard url.scheme == urlScheme, url.host == importHost,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let fileName = components.queryItems?.first(where: { $0.name == "file" })?.value,
              let dir = containerDirectory else { return nil }
        let fileURL = dir.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        return fileURL
    }

    /// App side: removes the file once `TournamentInvitationImportView` is
    /// done with it (success, failure, or the user dismissing without
    /// finishing), so each shared file is offered exactly once.
    static func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    /// Files older than this are dropped instead of offered — a share the
    /// user never followed up on shouldn't pop up weeks later.
    private static let maxPendingAge: TimeInterval = 7 * 24 * 60 * 60

    /// App side: the oldest shared file still waiting in the inbox, if any.
    /// `MainTabView` calls this whenever the app becomes active, so a share
    /// is picked up even when the extension couldn't open the app directly.
    static func nextPendingFile() -> URL? {
        guard let dir = containerDirectory,
              let files = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.creationDateKey], options: [.skipsHiddenFiles]
              ) else { return nil }
        let cutoff = Date.now.addingTimeInterval(-maxPendingAge)
        var pending: [(url: URL, created: Date)] = []
        for file in files {
            let created = (try? file.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            if created < cutoff {
                cleanup(file)
            } else {
                pending.append((file, created))
            }
        }
        return pending.min { $0.created < $1.created }?.url
    }
}
