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
}
