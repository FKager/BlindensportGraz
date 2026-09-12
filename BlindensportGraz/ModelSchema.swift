import SwiftData

/// The one place the app's SwiftData `Schema` is declared, so the app
/// (`BlindensportGrazApp`) and any non-view consumer that needs its own
/// read-only `ModelContainer` on the same store — currently the App Shortcuts
/// intents in `AppShortcuts.swift`, later a WidgetKit timeline provider —
/// stay in lockstep instead of hand-maintaining parallel model lists.
enum AppModelSchema {
    static let schema = Schema([
        User.self,
        SportEvent.self,
        Tournament.self,
        Training.self,
        Team.self,
        TeamMembership.self,
        EventParticipation.self,
        EventMembership.self,
        BudgetEntry.self,
        Member.self,
        EventImage.self,
        Attendance.self,
        TrainingFavorite.self,
        RoleChangeLog.self,
        ExpenseReceipt.self,
        // Self-service roster edits awaiting admin review
        // (architecture-review.md §5 P2).
        MemberChangeRequest.self,
        // Local-only outbox of not-yet-confirmed CloudKit writes
        // (architecture-review.md 2.2) — never itself synced.
        PendingPush.self
    ])

    /// Local store only — cross-user sharing is `CloudKitSync`'s manual
    /// public-database layer, not SwiftData's automatic mirroring.
    static var configuration: ModelConfiguration {
        ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, cloudKitDatabase: .none)
    }
}
