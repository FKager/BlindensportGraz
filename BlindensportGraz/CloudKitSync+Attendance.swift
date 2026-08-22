import CloudKit
import SwiftData
import Foundation

extension CloudKitSync {
    /// Shared by Training and Tournament attendance (both now backed by the
    /// single local `Attendance` model) — keeps the two existing CKRecord
    /// types ("TrainingAttendance"/"TournamentAttendance") for backward
    /// compatibility with already-synced data, picking the type via
    /// `attendance.event.kind` rather than introducing a new unified record
    /// type that old data wouldn't be found under.
    func pushAttendance(_ attendance: Attendance) {
        let recordType = attendance.event.kind == "tournament" ? CKSchema.Attendance.tournamentRecordType : CKSchema.Attendance.trainingRecordType
        let record = CKRecord(recordType: recordType, recordID: recordID(attendance.id))
        record[CKSchema.Attendance.trainingID] = attendance.event.kind == "tournament" ? nil : attendance.event.id.uuidString
        record[CKSchema.Attendance.tournamentID] = attendance.event.kind == "tournament" ? attendance.event.id.uuidString : nil
        record[CKSchema.Attendance.membershipID] = attendance.membership.id.uuidString
        record[CKSchema.Attendance.attended] = attendance.attended
        record[CKSchema.Attendance.recordedAt] = attendance.recordedAt
        record[CKSchema.Attendance.praeAmount] = attendance.praeAmount
        save(record)
    }

    /// Pulls both CKRecord types ("TrainingAttendance"/"TournamentAttendance",
    /// kept distinct for backward compatibility — see pushAttendance) into the
    /// single local `Attendance` model, resolving `event` via the now-generic
    /// `findEvent`.
    func pullAttendances(modelContext: ModelContext) async {
        for recordType in [CKSchema.Attendance.trainingRecordType, CKSchema.Attendance.tournamentRecordType] {
            let eventIDField = recordType == CKSchema.Attendance.tournamentRecordType ? CKSchema.Attendance.tournamentID : CKSchema.Attendance.trainingID
            for record in await fetchAll(recordType: recordType) {
                guard let id = UUID(uuidString: record.recordID.recordName),
                      let eventIDString = record[eventIDField] as? String, let eventID = UUID(uuidString: eventIDString),
                      let event = findEvent(eventID, modelContext: modelContext),
                      let membershipIDString = record[CKSchema.Attendance.membershipID] as? String, let membershipID = UUID(uuidString: membershipIDString),
                      let membership = findMembership(membershipID, modelContext: modelContext) else { continue }
                let attended = record[CKSchema.Attendance.attended] as? Bool ?? false
                let recordedAt = record[CKSchema.Attendance.recordedAt] as? Date ?? .now
                let praeAmount = record[CKSchema.Attendance.praeAmount] as? Double

                var descriptor = FetchDescriptor<Attendance>(predicate: #Predicate { $0.id == id })
                descriptor.fetchLimit = 1
                if let existing = try? modelContext.fetch(descriptor).first {
                    existing.attended = attended
                    existing.recordedAt = recordedAt
                    existing.praeAmount = praeAmount
                } else {
                    let attendance = Attendance(id: id, event: event, membership: membership,
                                                 attended: attended, recordedAt: recordedAt, praeAmount: praeAmount)
                    modelContext.insert(attendance)
                }
            }
        }
    }
}
