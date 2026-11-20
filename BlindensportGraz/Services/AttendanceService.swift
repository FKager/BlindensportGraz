import Foundation
import SwiftData

@MainActor
enum AttendanceService {
    @discardableResult
    static func save(_ attendance: Attendance, modelContext: ModelContext) -> Bool {
        PersistenceService.saveAndPush(modelContext: modelContext, modelName: "Attendance",
                                        failureMessage: "Anwesenheit konnte nicht gespeichert werden.") {
            SupabaseSync.shared.pushAttendance(attendance)
        }
    }

    /// Create-or-update (never duplicate) the `Attendance` row for
    /// `membership` at `event` and set its `attended` flag. Pure w.r.t.
    /// Supabase — inserts into `modelContext` but does NOT save or push, so
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

    /// Removes the attendance locally, then on the server. Reads the id and
    /// event kind before deleting: the model is gone once the push runs.
    @discardableResult
    static func delete(_ attendance: Attendance, modelContext: ModelContext) -> Bool {
        let id = attendance.id
        let isTournamentEvent = attendance.event.kind == "tournament"
        modelContext.delete(attendance)
        return PersistenceService.deleteAndPush(modelContext: modelContext, modelName: "Attendance",
                                                 failureMessage: "Anwesenheit konnte nicht gelöscht werden.") {
            SupabaseSync.shared.deleteAttendance(id: id, isTournamentEvent: isTournamentEvent)
        }
    }

    /// Called when a Training is marked "Abgesagt" (`Training.cancelledStatus`)
    /// — a cancelled training never happened, so its attendance records are
    /// deleted outright, not just reset (user request 2026-09-10, superseding
    /// the reset-in-place approach from earlier the same day). Deletes and
    /// pushes each row individually via `delete` above so the removal
    /// actually syncs and doesn't reappear on the next pull.
    @discardableResult
    static func deleteAll(for event: SportEvent, modelContext: ModelContext) -> Bool {
        var allSucceeded = true
        for attendance in event.attendances {
            if !delete(attendance, modelContext: modelContext) { allSucceeded = false }
        }
        return allSucceeded
    }
}
