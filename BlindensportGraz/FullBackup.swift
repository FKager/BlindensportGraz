import Foundation
import SwiftData

/// Whole-store JSON backup — architecture-review.md §5 P2, generalizing
/// `MemberBackup.swift`'s roster-only silent snapshot to every model type in
/// `AppModelSchema` (except `PendingPush`, which is local sync-machinery,
/// not club data). Admin-triggered (unlike `MemberBackup`'s automatic
/// create/delete-triggered snapshots), for disaster recovery, audit, or
/// migration.
///
/// Binary fields (`EventImage`/`ExpenseReceipt`'s `imageData`) are
/// deliberately excluded — same precedent as `CKFieldCoding`'s generic
/// record encoder on the RootCLI side, which doesn't handle CKAsset either.
/// Relationships are recorded as the related record's `id` (a UUID string),
/// exactly like every `CloudKitSync+*.swift` push function already does —
/// this file mirrors that field shape, just targeting a JSON dict instead
/// of a `CKRecord`.
///
/// The `encode*` functions below are pure (`Model` in, `[String: Any]` out)
/// and unit-tested; `export(modelContext:)` is the thin SwiftData-fetching
/// orchestration around them. See `FullBackupImporter` for the restore side.
enum FullBackup {
    static let formatVersion = 1

    private static let iso = ISO8601DateFormatter()
    static func string(_ date: Date) -> String { iso.string(from: date) }
    static func stringOrNull(_ date: Date?) -> Any { date.map { iso.string(from: $0) } ?? NSNull() }

    // MARK: - Decode helpers (pure) — used by FullBackupImporter

    static func string(_ dict: [String: Any], _ key: String) -> String { dict[key] as? String ?? "" }
    static func uuid(_ dict: [String: Any], _ key: String) -> UUID? { (dict[key] as? String).flatMap(UUID.init) }
    static func date(_ dict: [String: Any], _ key: String) -> Date? { (dict[key] as? String).flatMap { iso.date(from: $0) } }
    static func bool(_ dict: [String: Any], _ key: String) -> Bool { (dict[key] as? Bool) ?? false }
    static func int(_ dict: [String: Any], _ key: String) -> Int { (dict[key] as? Int) ?? 0 }
    static func intOrNil(_ dict: [String: Any], _ key: String) -> Int? { dict[key] as? Int }
    static func double(_ dict: [String: Any], _ key: String) -> Double? { dict[key] as? Double }
    static func stringList(_ dict: [String: Any], _ key: String) -> [String] { dict[key] as? [String] ?? [] }

    // MARK: - Encode (pure)

    static func encode(_ user: User) -> [String: Any] {
        // email/appleUserIdentifier deliberately excluded — see
        // CloudKitSync.swift's top doc comment: those never leave this
        // device, not even to CloudKit, so they don't belong in a shareable
        // backup file either.
        [
            "id": user.id.uuidString, "firstName": user.firstName, "lastName": user.lastName,
            "role": user.role.rawValue, "isGrazerVSCMember": user.isGrazerVSCMember, "isRoot": user.isRoot,
            "calendarToken": user.calendarToken, "createdAt": string(user.createdAt),
        ]
    }

    static func encode(_ member: Member) -> [String: Any] {
        [
            "id": member.id.uuidString, "firstName": member.firstName, "lastName": member.lastName,
            "street": member.street, "zip": member.zip, "city": member.city, "country": member.country,
            "email": member.email, "phone": member.phone, "memberNumber": member.memberNumber,
            "joinedAt": string(member.joinedAt), "notes": member.notes, "gender": member.gender,
            "title": member.title, "birthDate": stringOrNull(member.birthDate), "sportId": member.sportId,
            "svnr": member.svnr, "iban": member.iban,
            "lastMedicalExamination": stringOrNull(member.lastMedicalExamination),
            "defaultFunction": member.defaultFunction, "memberOfGVSC": member.memberOfGVSC,
        ]
    }

    static func encode(_ team: Team) -> [String: Any] {
        [
            "id": team.id.uuidString, "name": team.name, "sport": team.sport,
            "descriptionText": team.descriptionText, "createdAt": string(team.createdAt),
        ]
    }

    static func encode(_ membership: TeamMembership) -> [String: Any] {
        [
            "id": membership.id.uuidString, "teamID": membership.team.id.uuidString,
            "userID": membership.user.map { $0.id.uuidString } ?? NSNull(),
            "memberID": membership.member.map { $0.id.uuidString } ?? NSNull(),
            "role": membership.role.rawValue, "joinedAt": string(membership.joinedAt),
        ]
    }

    /// Shared field set for the SportEvent base class — covers plain events,
    /// and the fields Training/Tournament also carry (see their own
    /// `encode` overloads for the fields on top of these).
    private static func encodeEventFields(_ event: SportEvent) -> [String: Any] {
        [
            "id": event.id.uuidString, "title": event.title, "sport": event.sport,
            "location": event.location, "street": event.street, "zip": event.zip, "city": event.city,
            "country": event.country, "startDate": string(event.startDate), "endDate": string(event.endDate),
            "notes": event.notes, "createdBy": event.createdBy, "createdAt": string(event.createdAt),
            "teamIDs": event.teams.map { $0.id.uuidString },
        ]
    }

    static func encode(_ event: SportEvent) -> [String: Any] { encodeEventFields(event) }

    static func encode(_ training: Training) -> [String: Any] {
        var fields = encodeEventFields(training)
        fields["durationMinutes"] = training.durationMinutes
        fields["focusArea"] = training.focusArea
        fields["status"] = training.status
        return fields
    }

    static func encode(_ tournament: Tournament) -> [String: Any] {
        var fields = encodeEventFields(tournament)
        fields["maxTeams"] = tournament.maxTeams
        fields["status"] = tournament.status
        return fields
    }

    static func encode(_ participation: EventParticipation) -> [String: Any] {
        [
            "id": participation.id.uuidString, "userID": participation.user.id.uuidString,
            "eventID": participation.event.id.uuidString, "status": participation.status,
            "registeredAt": string(participation.registeredAt),
        ]
    }

    static func encode(_ membership: EventMembership) -> [String: Any] {
        [
            "id": membership.id.uuidString, "eventID": membership.event.id.uuidString,
            "userID": membership.user.map { $0.id.uuidString } ?? NSNull(),
            "memberID": membership.member.map { $0.id.uuidString } ?? NSNull(),
            "addedAt": string(membership.addedAt),
        ]
    }

    static func encode(_ entry: BudgetEntry) -> [String: Any] {
        [
            "id": entry.id.uuidString, "category": entry.category.rawValue, "amount": entry.amount,
            "date": string(entry.date), "note": entry.note,
            "eventID": entry.event.map { $0.id.uuidString } ?? NSNull(),
            "createdBy": entry.createdBy, "createdAt": string(entry.createdAt),
        ]
    }

    static func encode(_ attendance: Attendance) -> [String: Any] {
        [
            "id": attendance.id.uuidString, "eventID": attendance.event.id.uuidString,
            "membershipID": attendance.membership.id.uuidString, "attended": attendance.attended,
            "recordedAt": string(attendance.recordedAt), "praeAmount": attendance.praeAmount ?? NSNull(),
        ]
    }

    static func encode(_ image: EventImage) -> [String: Any] {
        [
            "id": image.id.uuidString, "uploadedBy": image.uploadedBy, "uploadedAt": string(image.uploadedAt),
            "eventID": image.event.map { $0.id.uuidString } ?? NSNull(),
        ]
    }

    static func encode(_ receipt: ExpenseReceipt) -> [String: Any] {
        [
            "id": receipt.id.uuidString, "uploadedBy": receipt.uploadedBy, "uploadedAt": string(receipt.uploadedAt),
            "note": receipt.note, "month": receipt.month ?? NSNull(), "year": receipt.year ?? NSNull(),
            "tournamentID": receipt.tournament.map { $0.id.uuidString } ?? NSNull(),
        ]
    }

    static func encode(_ favorite: TrainingFavorite) -> [String: Any] {
        [
            "id": favorite.id.uuidString, "title": favorite.title, "sport": favorite.sport,
            "startHour": favorite.startHour, "startMinute": favorite.startMinute,
            "endHour": favorite.endHour, "endMinute": favorite.endMinute, "weekday": favorite.weekday,
            "location": favorite.location, "street": favorite.street, "zip": favorite.zip,
            "city": favorite.city, "country": favorite.country,
            "teamIDs": favorite.teams.map { $0.id.uuidString }, "lastUsedAt": string(favorite.lastUsedAt),
        ]
    }

    static func encode(_ entry: RoleChangeLog) -> [String: Any] {
        [
            "id": entry.id.uuidString, "userID": entry.userID.uuidString, "oldRole": entry.oldRole,
            "newRole": entry.newRole, "changedBy": entry.changedBy, "changedAt": string(entry.changedAt),
        ]
    }

    static func encode(_ request: MemberChangeRequest) -> [String: Any] {
        [
            "id": request.id.uuidString, "memberID": request.memberID.uuidString,
            "requestedBy": request.requestedBy, "requestedAt": string(request.requestedAt),
            "status": request.status, "reviewedBy": request.reviewedBy,
            "reviewedAt": stringOrNull(request.reviewedAt),
            "firstName": request.firstName, "lastName": request.lastName, "title": request.title,
            "gender": request.gender, "birthDate": stringOrNull(request.birthDate), "street": request.street,
            "zip": request.zip, "city": request.city, "country": request.country, "email": request.email,
            "phone": request.phone, "sportId": request.sportId, "svnr": request.svnr, "iban": request.iban,
            "lastMedicalExamination": stringOrNull(request.lastMedicalExamination),
        ]
    }

    // MARK: - Export orchestration

    /// Every type bucket, in the same dependency order `CloudKitSync.syncAll`
    /// pulls in (User/Member/Team before TeamMembership before Attendance,
    /// etc.) — `FullBackupImporter.restore` relies on the file preserving
    /// this order so a dependency is always inserted before whatever
    /// references it.
    static func export(modelContext: ModelContext) throws -> URL {
        let events = (try? modelContext.fetch(FetchDescriptor<SportEvent>(
            predicate: #Predicate { $0.kind == "event" }
        ))) ?? []

        let records: [String: [[String: Any]]] = [
            "User": ((try? modelContext.fetch(FetchDescriptor<User>())) ?? []).map(encode),
            "Member": ((try? modelContext.fetch(FetchDescriptor<Member>())) ?? []).map(encode),
            "Team": ((try? modelContext.fetch(FetchDescriptor<Team>())) ?? []).map(encode),
            "TeamMembership": ((try? modelContext.fetch(FetchDescriptor<TeamMembership>())) ?? []).map(encode),
            "Event": events.map(encode),
            "Training": ((try? modelContext.fetch(FetchDescriptor<Training>())) ?? []).map(encode),
            "Tournament": ((try? modelContext.fetch(FetchDescriptor<Tournament>())) ?? []).map(encode),
            "EventImage": ((try? modelContext.fetch(FetchDescriptor<EventImage>())) ?? []).map(encode),
            "ExpenseReceipt": ((try? modelContext.fetch(FetchDescriptor<ExpenseReceipt>())) ?? []).map(encode),
            "EventParticipation": ((try? modelContext.fetch(FetchDescriptor<EventParticipation>())) ?? []).map(encode),
            "EventMembership": ((try? modelContext.fetch(FetchDescriptor<EventMembership>())) ?? []).map(encode),
            "BudgetEntry": ((try? modelContext.fetch(FetchDescriptor<BudgetEntry>())) ?? []).map(encode),
            "Attendance": ((try? modelContext.fetch(FetchDescriptor<Attendance>())) ?? []).map(encode),
            "TrainingFavorite": ((try? modelContext.fetch(FetchDescriptor<TrainingFavorite>())) ?? []).map(encode),
            "RoleChangeLog": ((try? modelContext.fetch(FetchDescriptor<RoleChangeLog>())) ?? []).map(encode),
            "MemberChangeRequest": ((try? modelContext.fetch(FetchDescriptor<MemberChangeRequest>())) ?? []).map(encode),
        ]

        let bundle: [String: Any] = [
            "formatVersion": formatVersion,
            "exportedAt": string(.now),
            "counts": records.mapValues { $0.count },
            "records": records,
        ]

        let data = try JSONSerialization.data(withJSONObject: bundle, options: [.prettyPrinted, .sortedKeys])
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("BlindensportGraz-Backup-\(formatter.string(from: .now)).json")
        try data.write(to: url, options: .atomic)
        return url
    }
}
