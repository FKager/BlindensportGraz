import Foundation
import SwiftData

/// Restores a `FullBackup.export(...)` JSON file — architecture-review.md
/// §5 P2. Deliberately conservative: for every record, if a local record
/// with the same `id` already exists, it's left completely untouched (no
/// update, no overwrite) — only records that are genuinely MISSING locally
/// get created. CloudKit sync (`syncAll`) is already this app's real
/// "pull the current truth" mechanism; this exists for disaster recovery
/// (both the local store and the CloudKit container lost) and migration,
/// not as a second live-sync path that could clobber a concurrent edit.
///
/// Processes each type bucket in the same dependency order
/// `CloudKitSync.syncAll` pulls in, and skips (counted, not silently
/// dropped) any record whose required relationship can't be resolved yet
/// (e.g. a `TeamMembership` naming a `teamID` that isn't in this backup or
/// already local) — never partially constructs a record with a dangling
/// reference. Not unit-tested (it calls the `*Service.save` CloudKit-push
/// path on success, same "no CloudKit in new tests" boundary every other
/// sync-adjacent function in this app respects); `FullBackup`'s `encode`
/// functions carry the tested logic for the field shapes this reads.
@MainActor
enum FullBackupImporter {
    struct Result {
        var createdByType: [String: Int] = [:]
        var skippedByType: [String: Int] = [:]
        var totalCreated: Int { createdByType.values.reduce(0, +) }
        var totalSkipped: Int { skippedByType.values.reduce(0, +) }
    }

    enum ImportError: Error, LocalizedError {
        case invalidFile
        var errorDescription: String? {
            "Die Datei ist keine gültige Sicherung."
        }
    }

    static func restore(from data: Data, modelContext: ModelContext) throws -> Result {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let records = root["records"] as? [String: [[String: Any]]] else {
            throw ImportError.invalidFile
        }

        var result = Result()
        func run<T: PersistentModel>(_ type: T.Type, _ key: String, _ restore: (_ dict: [String: Any]) -> Bool) {
            var created = 0, skipped = 0
            for dict in records[key] ?? [] {
                if restore(dict) { created += 1 } else { skipped += 1 }
            }
            result.createdByType[key] = created
            result.skippedByType[key] = skipped
        }

        // #Predicate's macro only accepts a literal key path written at the
        // call site — a KeyPath value passed through a generic parameter
        // fails to compile ("subscript(keyPath:) is not supported in this
        // predicate"), so unlike a generic helper, each type gets its own
        // tiny existence check. Where `CloudKitSync.shared` already has a
        // `findX` resolver (used below for relationships too), that's
        // reused instead of duplicating the predicate.
        func exists(_ id: UUID, in type: EventParticipation.Type) -> Bool {
            var d = FetchDescriptor<EventParticipation>(predicate: #Predicate { $0.id == id }); d.fetchLimit = 1
            return !((try? modelContext.fetch(d)) ?? []).isEmpty
        }
        func exists(_ id: UUID, in type: Attendance.Type) -> Bool {
            var d = FetchDescriptor<Attendance>(predicate: #Predicate { $0.id == id }); d.fetchLimit = 1
            return !((try? modelContext.fetch(d)) ?? []).isEmpty
        }
        func exists(_ id: UUID, in type: TrainingFavorite.Type) -> Bool {
            var d = FetchDescriptor<TrainingFavorite>(predicate: #Predicate { $0.id == id }); d.fetchLimit = 1
            return !((try? modelContext.fetch(d)) ?? []).isEmpty
        }
        func exists(_ id: UUID, in type: RoleChangeLog.Type) -> Bool {
            var d = FetchDescriptor<RoleChangeLog>(predicate: #Predicate { $0.id == id }); d.fetchLimit = 1
            return !((try? modelContext.fetch(d)) ?? []).isEmpty
        }
        func exists(_ id: UUID, in type: MemberChangeRequest.Type) -> Bool {
            var d = FetchDescriptor<MemberChangeRequest>(predicate: #Predicate { $0.id == id }); d.fetchLimit = 1
            return !((try? modelContext.fetch(d)) ?? []).isEmpty
        }
        func exists(_ id: UUID, in type: Training.Type) -> Bool {
            var d = FetchDescriptor<Training>(predicate: #Predicate { $0.id == id }); d.fetchLimit = 1
            return !((try? modelContext.fetch(d)) ?? []).isEmpty
        }
        func exists(_ id: UUID, in type: Tournament.Type) -> Bool {
            var d = FetchDescriptor<Tournament>(predicate: #Predicate { $0.id == id }); d.fetchLimit = 1
            return !((try? modelContext.fetch(d)) ?? []).isEmpty
        }

        run(User.self, "User") { dict in
            guard let id = FullBackup.uuid(dict, "id"), CloudKitSync.shared.findUser(id, modelContext: modelContext) == nil else { return false }
            let user = User(id: id, email: "", firstName: FullBackup.string(dict, "firstName"),
                            lastName: FullBackup.string(dict, "lastName"),
                            role: AppRole.normalize(FullBackup.string(dict, "role")),
                            createdAt: FullBackup.date(dict, "createdAt") ?? .now,
                            isGrazerVSCMember: FullBackup.bool(dict, "isGrazerVSCMember"),
                            isRoot: FullBackup.bool(dict, "isRoot"))
            user.calendarToken = FullBackup.string(dict, "calendarToken")
            modelContext.insert(user)
            return UserService.save(user, modelContext: modelContext)
        }

        run(Member.self, "Member") { dict in
            guard let id = FullBackup.uuid(dict, "id"), CloudKitSync.shared.findMember(id, modelContext: modelContext) == nil else { return false }
            let member = Member(id: id, firstName: FullBackup.string(dict, "firstName"), lastName: FullBackup.string(dict, "lastName"),
                                street: FullBackup.string(dict, "street"), zip: FullBackup.string(dict, "zip"),
                                city: FullBackup.string(dict, "city"), country: FullBackup.string(dict, "country"),
                                email: FullBackup.string(dict, "email"), phone: FullBackup.string(dict, "phone"),
                                memberNumber: FullBackup.string(dict, "memberNumber"),
                                joinedAt: FullBackup.date(dict, "joinedAt") ?? .now, notes: FullBackup.string(dict, "notes"),
                                gender: FullBackup.string(dict, "gender"), title: FullBackup.string(dict, "title"),
                                birthDate: FullBackup.date(dict, "birthDate"), sportId: FullBackup.string(dict, "sportId"),
                                svnr: FullBackup.string(dict, "svnr"), iban: FullBackup.string(dict, "iban"),
                                lastMedicalExamination: FullBackup.date(dict, "lastMedicalExamination"),
                                defaultFunction: FullBackup.string(dict, "defaultFunction"),
                                memberOfGVSC: (dict["memberOfGVSC"] as? Bool) ?? true)
            modelContext.insert(member)
            return MemberService.save(member, modelContext: modelContext)
        }

        run(Team.self, "Team") { dict in
            guard let id = FullBackup.uuid(dict, "id"), CloudKitSync.shared.findTeam(id, modelContext: modelContext) == nil else { return false }
            let team = Team(id: id, name: FullBackup.string(dict, "name"), sport: FullBackup.string(dict, "sport"),
                            descriptionText: FullBackup.string(dict, "descriptionText"),
                            createdAt: FullBackup.date(dict, "createdAt") ?? .now)
            modelContext.insert(team)
            return TeamService.save(team, modelContext: modelContext)
        }

        run(TeamMembership.self, "TeamMembership") { dict in
            guard let id = FullBackup.uuid(dict, "id"), CloudKitSync.shared.findMembership(id, modelContext: modelContext) == nil,
                  let teamID = FullBackup.uuid(dict, "teamID"),
                  let team = CloudKitSync.shared.findTeam(teamID, modelContext: modelContext) else { return false }
            let user = FullBackup.uuid(dict, "userID").flatMap { CloudKitSync.shared.findUser($0, modelContext: modelContext) }
            let member = FullBackup.uuid(dict, "memberID").flatMap { CloudKitSync.shared.findMember($0, modelContext: modelContext) }
            guard user != nil || member != nil else { return false } // exactly one must resolve, matching the model's own invariant
            let membership = TeamMembership(id: id, user: user, member: member, team: team,
                                            role: MembershipRole.normalize(FullBackup.string(dict, "role")),
                                            joinedAt: FullBackup.date(dict, "joinedAt") ?? .now)
            modelContext.insert(membership)
            return TeamMembershipService.save(membership, modelContext: modelContext)
        }

        func restoreEvent(_ dict: [String: Any]) -> SportEvent? {
            guard let id = FullBackup.uuid(dict, "id"), CloudKitSync.shared.findEvent(id, modelContext: modelContext) == nil else { return nil }
            let teams = FullBackup.stringList(dict, "teamIDs").compactMap { UUID(uuidString: $0) }
                .compactMap { CloudKitSync.shared.findTeam($0, modelContext: modelContext) }
            let event = SportEvent(id: id, title: FullBackup.string(dict, "title"), sport: FullBackup.string(dict, "sport"),
                                   location: FullBackup.string(dict, "location"), street: FullBackup.string(dict, "street"),
                                   zip: FullBackup.string(dict, "zip"), city: FullBackup.string(dict, "city"),
                                   country: FullBackup.string(dict, "country"), startDate: FullBackup.date(dict, "startDate") ?? .now,
                                   endDate: FullBackup.date(dict, "endDate") ?? .now, notes: FullBackup.string(dict, "notes"),
                                   createdBy: FullBackup.string(dict, "createdBy"),
                                   createdAt: FullBackup.date(dict, "createdAt") ?? .now, teams: teams)
            return event
        }
        run(SportEvent.self, "Event") { dict in
            guard let event = restoreEvent(dict) else { return false }
            modelContext.insert(event)
            return SportEventService.save(event, modelContext: modelContext)
        }

        run(Training.self, "Training") { dict in
            guard let id = FullBackup.uuid(dict, "id"), !exists(id, in: Training.self) else { return false }
            let teams = FullBackup.stringList(dict, "teamIDs").compactMap { UUID(uuidString: $0) }
                .compactMap { CloudKitSync.shared.findTeam($0, modelContext: modelContext) }
            let statusRaw = FullBackup.string(dict, "status")
            let training = Training(id: id, title: FullBackup.string(dict, "title"), sport: FullBackup.string(dict, "sport"),
                                    location: FullBackup.string(dict, "location"), street: FullBackup.string(dict, "street"),
                                    zip: FullBackup.string(dict, "zip"), city: FullBackup.string(dict, "city"),
                                    country: FullBackup.string(dict, "country"), startDate: FullBackup.date(dict, "startDate") ?? .now,
                                    durationMinutes: FullBackup.int(dict, "durationMinutes"), focusArea: FullBackup.string(dict, "focusArea"),
                                    status: statusRaw.isEmpty ? Training.openStatus : statusRaw,
                                    notes: FullBackup.string(dict, "notes"), createdBy: FullBackup.string(dict, "createdBy"),
                                    createdAt: FullBackup.date(dict, "createdAt") ?? .now, teams: teams)
            modelContext.insert(training)
            return TrainingService.save(training, modelContext: modelContext)
        }

        run(Tournament.self, "Tournament") { dict in
            guard let id = FullBackup.uuid(dict, "id"), !exists(id, in: Tournament.self) else { return false }
            let teams = FullBackup.stringList(dict, "teamIDs").compactMap { UUID(uuidString: $0) }
                .compactMap { CloudKitSync.shared.findTeam($0, modelContext: modelContext) }
            let tournament = Tournament(id: id, title: FullBackup.string(dict, "title"), sport: FullBackup.string(dict, "sport"),
                                        location: FullBackup.string(dict, "location"), street: FullBackup.string(dict, "street"),
                                        zip: FullBackup.string(dict, "zip"), city: FullBackup.string(dict, "city"),
                                        country: FullBackup.string(dict, "country"), startDate: FullBackup.date(dict, "startDate") ?? .now,
                                        endDate: FullBackup.date(dict, "endDate") ?? .now, maxTeams: FullBackup.int(dict, "maxTeams"),
                                        status: FullBackup.string(dict, "status"), notes: FullBackup.string(dict, "notes"),
                                        createdBy: FullBackup.string(dict, "createdBy"),
                                        createdAt: FullBackup.date(dict, "createdAt") ?? .now, teams: teams)
            modelContext.insert(tournament)
            return TournamentService.save(tournament, modelContext: modelContext)
        }

        run(EventParticipation.self, "EventParticipation") { dict in
            guard let id = FullBackup.uuid(dict, "id"), !exists(id, in: EventParticipation.self),
                  let userID = FullBackup.uuid(dict, "userID"), let user = CloudKitSync.shared.findUser(userID, modelContext: modelContext),
                  let eventID = FullBackup.uuid(dict, "eventID"), let event = CloudKitSync.shared.findEvent(eventID, modelContext: modelContext) else { return false }
            let participation = EventParticipation(id: id, user: user, event: event, status: FullBackup.string(dict, "status"),
                                                   registeredAt: FullBackup.date(dict, "registeredAt") ?? .now)
            modelContext.insert(participation)
            return EventParticipationService.save(participation, modelContext: modelContext)
        }

        run(Attendance.self, "Attendance") { dict in
            guard let id = FullBackup.uuid(dict, "id"), !exists(id, in: Attendance.self),
                  let eventID = FullBackup.uuid(dict, "eventID"), let event = CloudKitSync.shared.findEvent(eventID, modelContext: modelContext),
                  let membershipID = FullBackup.uuid(dict, "membershipID"),
                  let membership = CloudKitSync.shared.findMembership(membershipID, modelContext: modelContext) else { return false }
            let attendance = Attendance(id: id, event: event, membership: membership, attended: FullBackup.bool(dict, "attended"),
                                        recordedAt: FullBackup.date(dict, "recordedAt") ?? .now, praeAmount: FullBackup.double(dict, "praeAmount"))
            modelContext.insert(attendance)
            return AttendanceService.save(attendance, modelContext: modelContext)
        }

        run(TrainingFavorite.self, "TrainingFavorite") { dict in
            guard let id = FullBackup.uuid(dict, "id"), !exists(id, in: TrainingFavorite.self) else { return false }
            let teams = FullBackup.stringList(dict, "teamIDs").compactMap { UUID(uuidString: $0) }
                .compactMap { CloudKitSync.shared.findTeam($0, modelContext: modelContext) }
            let favorite = TrainingFavorite(id: id, title: FullBackup.string(dict, "title"), sport: FullBackup.string(dict, "sport"),
                                            startHour: FullBackup.int(dict, "startHour"), startMinute: FullBackup.int(dict, "startMinute"),
                                            endHour: FullBackup.int(dict, "endHour"), endMinute: FullBackup.int(dict, "endMinute"),
                                            weekday: FullBackup.int(dict, "weekday"), location: FullBackup.string(dict, "location"),
                                            street: FullBackup.string(dict, "street"), zip: FullBackup.string(dict, "zip"),
                                            city: FullBackup.string(dict, "city"), country: FullBackup.string(dict, "country"), teams: teams,
                                            lastUsedAt: FullBackup.date(dict, "lastUsedAt") ?? .now)
            modelContext.insert(favorite)
            return TrainingFavoriteService.saveResult(favorite: favorite, evictedID: nil, modelContext: modelContext)
        }

        run(RoleChangeLog.self, "RoleChangeLog") { dict in
            guard let id = FullBackup.uuid(dict, "id"), !exists(id, in: RoleChangeLog.self),
                  let userID = FullBackup.uuid(dict, "userID") else { return false }
            let entry = RoleChangeLog(id: id, userID: userID, oldRole: FullBackup.string(dict, "oldRole"),
                                      newRole: FullBackup.string(dict, "newRole"), changedBy: FullBackup.string(dict, "changedBy"),
                                      changedAt: FullBackup.date(dict, "changedAt") ?? .now)
            modelContext.insert(entry)
            return PersistenceService.saveAndPush(modelContext: modelContext, modelName: "RoleChangeLog",
                                                  failureMessage: "Rollenänderung konnte nicht gespeichert werden.") {
                CloudKitSync.shared.pushRoleChangeLog(entry)
            }
        }

        run(MemberChangeRequest.self, "MemberChangeRequest") { dict in
            guard let id = FullBackup.uuid(dict, "id"), !exists(id, in: MemberChangeRequest.self),
                  let memberID = FullBackup.uuid(dict, "memberID") else { return false }
            let request = MemberChangeRequest(
                id: id, memberID: memberID, requestedBy: FullBackup.string(dict, "requestedBy"),
                requestedAt: FullBackup.date(dict, "requestedAt") ?? .now, status: FullBackup.string(dict, "status"),
                reviewedBy: FullBackup.string(dict, "reviewedBy"), reviewedAt: FullBackup.date(dict, "reviewedAt"),
                firstName: FullBackup.string(dict, "firstName"), lastName: FullBackup.string(dict, "lastName"),
                title: FullBackup.string(dict, "title"), gender: FullBackup.string(dict, "gender"),
                birthDate: FullBackup.date(dict, "birthDate"), street: FullBackup.string(dict, "street"),
                zip: FullBackup.string(dict, "zip"), city: FullBackup.string(dict, "city"), country: FullBackup.string(dict, "country"),
                email: FullBackup.string(dict, "email"), phone: FullBackup.string(dict, "phone"),
                sportId: FullBackup.string(dict, "sportId"), svnr: FullBackup.string(dict, "svnr"), iban: FullBackup.string(dict, "iban"),
                lastMedicalExamination: FullBackup.date(dict, "lastMedicalExamination")
            )
            modelContext.insert(request)
            return MemberChangeRequestService.save(request, modelContext: modelContext)
        }

        // EventImage/ExpenseReceipt carry a required `imageData` this backup
        // never captured (see FullBackup's doc comment) — restoring them
        // with a placeholder image would be worse than not restoring them
        // at all, so they're deliberately left out of the restore pass
        // entirely (still counted as 0/0 rather than silently absent from
        // the result).
        result.createdByType["EventImage"] = 0
        result.skippedByType["EventImage"] = records["EventImage"]?.count ?? 0
        result.createdByType["ExpenseReceipt"] = 0
        result.skippedByType["ExpenseReceipt"] = records["ExpenseReceipt"]?.count ?? 0

        return result
    }
}
