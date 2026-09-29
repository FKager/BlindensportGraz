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
