import Foundation
import SwiftData

/// No `delete` — `CloudKitSync` never had a delete path for Attendance
/// records; not invented here, matching Phase 6's same scoping.
@MainActor
enum AttendanceService {
    @discardableResult
    static func save(_ attendance: Attendance, modelContext: ModelContext) -> Bool {
        PersistenceService.saveAndPush(modelContext: modelContext, modelName: "Attendance",
                                        failureMessage: "Anwesenheit konnte nicht gespeichert werden.") {
            CloudKitSync.shared.pushAttendance(attendance)
        }
    }

    /// Create-or-update (never duplicate) the `Attendance` row for
    /// `membership` at `event` and set its `attended` flag. Pure w.r.t.
    /// CloudKit — inserts into `modelContext` but does NOT save or push, so
    /// it's unit-testable in isolation. Callers that want persistence use
    /// `setAttended`.
    @discardableResult
    static func mark(_ attended: Bool, for membership: TeamMembership, at event: SportEvent,
                     modelContext: ModelContext) -> Attendance {
        if let existing = event.attendances.first(where: { $0.membership.id == membership.id }) {
            existing.attended = attended
            return existing
        }
        let record = Attendance(event: event, membership: membership, attended: attended)
        modelContext.insert(record)
        return record
    }

    /// `mark` + persist + push — the single call the Anwesenheit toggles in
    /// `TrainingDetailView`/`TournamentDetailView` and `AttendanceRollCallView`
    /// all go through, so "lazily created on first toggle" lives in one place
    /// (architecture-review.md §1.2).
    @discardableResult
    static func setAttended(_ attended: Bool, for membership: TeamMembership, at event: SportEvent,
                            modelContext: ModelContext) -> Bool {
        let record = mark(attended, for: membership, at: event, modelContext: modelContext)
        return save(record, modelContext: modelContext)
    }
}
