import Foundation
import SwiftData

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

    /// Caller has already called `modelContext.delete(attendance)` before
    /// this — same contract as every other `*Service.delete`. Reads
    /// `attendance.id`/`.event.kind` up front (not inside the push closure)
    /// for the same reason `TrainingService.delete` captures `training.id`
    /// first: the model may already be staged for deletion by the time the
    /// closure actually runs.
    ///
    /// Was a real gap until 2026-09-10 (`CloudKitSync` had no delete path
    /// for Attendance at all — deleting a row locally just came back on the
    /// next pull); added specifically so `deleteAll` below can remove a
    /// cancelled training's attendance for real instead of only resetting
    /// its fields.
    @discardableResult
    static func delete(_ attendance: Attendance, modelContext: ModelContext) -> Bool {
        let id = attendance.id
        let isTournamentEvent = attendance.event.kind == "tournament"
        return PersistenceService.deleteAndPush(modelContext: modelContext, modelName: "Attendance",
                                                 failureMessage: "Anwesenheit konnte nicht gelöscht werden.") {
            CloudKitSync.shared.deleteAttendance(id: id, isTournamentEvent: isTournamentEvent)
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
            modelContext.delete(attendance)
            if !delete(attendance, modelContext: modelContext) { allSucceeded = false }
        }
        return allSucceeded
    }
}
