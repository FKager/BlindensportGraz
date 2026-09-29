import Foundation
import SwiftData

/// Singleton-style shared welcome note, shown to every logged-in user on
/// launch (see `RootView`) — authored by an admin and synced via CloudKit's
/// public database like every other record in this app (`CloudKitSync+
/// WelcomeContent.swift`), NOT a per-device security-scoped bookmark to a
/// picked file (that approach was tried and rejected — it only ever worked
/// on the one device that picked the file). The actual authoring source is
/// still a `welcome.md` the admin edits in their own iCloud Drive
/// (`WelcomeFileWatcher.swift`); whichever admin device can see that file
/// pushes its content here, and every other device just displays whatever
/// this record already holds.
@Model
final class WelcomeContent {
    @Attribute(.unique) var id: UUID = WelcomeContent.sharedID
    var markdown: String = ""
    var isEnabled: Bool = false
    var updatedAt: Date = Date.now

    init(id: UUID = WelcomeContent.sharedID, markdown: String = "", isEnabled: Bool = false, updatedAt: Date = .now) {
        self.id = id
        self.markdown = markdown
        self.isEnabled = isEnabled
        self.updatedAt = updatedAt
    }
}

extension WelcomeContent {
    /// Fixed well-known id — the app only ever has one welcome note, shared
    /// by every user, so every device's push/pull targets the exact same
    /// CKRecord instead of each admin device minting its own.
    static let sharedID = UUID(uuidString: "00000000-0000-0000-0000-00000000C0DE")!

    static func current(in modelContext: ModelContext) -> WelcomeContent? {
        var descriptor = FetchDescriptor<WelcomeContent>(predicate: #Predicate { $0.id == sharedID })
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    /// Fetches the singleton row, inserting a blank/disabled one locally
    /// (not yet pushed) if none exists yet — so callers always have
    /// something to mutate and then explicitly save/push.
    static func fetchOrCreate(in modelContext: ModelContext) -> WelcomeContent {
        if let existing = current(in: modelContext) { return existing }
        let content = WelcomeContent()
        modelContext.insert(content)
        return content
    }
}
