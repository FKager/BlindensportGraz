import Foundation
import SwiftData

/// Automatic, silent JSON snapshots of the whole Member roster, taken
/// whenever a `Member` is created or deleted — a local safety net an admin
/// can recover from without having to have manually exported first. Written
/// to the app's Documents directory (unlike `MemberImportExport.exportFile`'s
/// temp-directory ShareLink files, which iOS can purge at any time) under a
/// `MemberBackups` subfolder, exposed to the Files app via
/// `UIFileSharingEnabled`/`LSSupportsOpeningDocumentsInPlace` (Info.plist) so
/// an admin can browse/export a snapshot without any extra in-app UI. Reuses
/// `MemberImportExport`'s `MemberIO` JSON shape, so a backup file can be fed
/// straight back through the existing `.fileImporter` import flow if it's
/// ever actually needed — no separate restore code to maintain.
enum MemberBackup {
    private static let folderName = "MemberBackups"
    // Caps disk usage for a feature that fires on every create/delete — an
    // actively administered roster could otherwise accumulate an unbounded
    // number of near-duplicate snapshots over time.
    private static let maxBackups = 30

    private static var backupsDirectory: URL? {
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        let directory = documents.appendingPathComponent(folderName, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Writes a timestamped snapshot of `members`, then prunes anything
    /// beyond the `maxBackups` most recent files. Best-effort: failures are
    /// swallowed (matching this app's existing `try?`-everywhere convention
    /// for non-critical local I/O) since a missed backup should never block
    /// the create/delete the caller is actually performing.
    static func snapshot(members: [Member]) {
        guard let directory = backupsDirectory,
              let data = try? MemberImportExport.encodedJSON(for: members) else { return }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss-SSS"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let url = directory.appendingPathComponent("mitglieder-\(formatter.string(from: .now)).json")
        try? data.write(to: url, options: .atomic)

        prune(directory: directory)
    }

    private static func prune(directory: URL) {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }
        let sorted = files.sorted { lhs, rhs in
            let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            return lhsDate > rhsDate
        }
        for stale in sorted.dropFirst(maxBackups) {
            try? FileManager.default.removeItem(at: stale)
        }
    }
}
