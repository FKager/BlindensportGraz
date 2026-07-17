import CloudKit
import SwiftData
import Foundation

/// Shares Team/Event/Training/Tournament/Membership/Participation/ClubMember/
/// EventImage data across different users' Apple IDs via CloudKit's public
/// database.
/// SwiftData's own CloudKit integration only mirrors the private, per-user
/// database, so it can't do this — this layer pushes/pulls plain CKRecords
/// instead, matching local SwiftData objects by their stable `id` (used as
/// the CKRecord name).
///
/// Only non-sensitive identity fields (username, displayName, role,
/// isGrazerVSCMember) are ever published for a User — email and the Apple
/// identifier stay device-local. The ClubMember roster (name/address/contact
/// details) is admin-managed data, synced so every admin's device and the
/// account-creation match check see the same roster.
@MainActor
final class CloudKitSync {
    static let shared = CloudKitSync()

    private let container = CKContainer(identifier: "iCloud.it.a11y.BlindensportGraz")
    private var publicDB: CKDatabase { container.publicCloudDatabase }

    private init() {}

    // MARK: - Push

    func pushTeam(_ team: Team) {
        let record = CKRecord(recordType: "Team", recordID: recordID(team.id))
        record["name"] = team.name
        record["sport"] = team.sport
        record["descriptionText"] = team.descriptionText
        record["createdAt"] = team.createdAt
        save(record)
    }

    func pushMembership(_ membership: TeamMembership) {
        let record = CKRecord(recordType: "TeamMembership", recordID: recordID(membership.id))
        record["userID"] = membership.user?.id.uuidString
        record["clubMemberID"] = membership.clubMember?.id.uuidString
        record["teamID"] = membership.team.id.uuidString
        record["role"] = membership.role
        record["joinedAt"] = membership.joinedAt
        save(record)
    }

    func pushEvent(_ event: SportEvent) {
        let record = CKRecord(recordType: "SportEvent", recordID: recordID(event.id))
        record["title"] = event.title
        record["sport"] = event.sport
        record["location"] = event.location
        record["startDate"] = event.startDate
        record["endDate"] = event.endDate
        record["notes"] = event.notes
        record["createdBy"] = event.createdBy
        record["createdAt"] = event.createdAt
        record["teamIDs"] = event.teams.map { $0.id.uuidString }
        save(record)
    }

    func pushTraining(_ training: Training) {
        let record = CKRecord(recordType: "Training", recordID: recordID(training.id))
        record["title"] = training.title
        record["sport"] = training.sport
        record["location"] = training.location
        record["startDate"] = training.startDate
        record["durationMinutes"] = training.durationMinutes
        record["focusArea"] = training.focusArea
        record["notes"] = training.notes
        record["createdBy"] = training.createdBy
        record["createdAt"] = training.createdAt
        record["teamIDs"] = training.teams.map { $0.id.uuidString }
        save(record)
    }

    func pushTrainingAttendance(_ attendance: TrainingAttendance) {
        let record = CKRecord(recordType: "TrainingAttendance", recordID: recordID(attendance.id))
        record["trainingID"] = attendance.training.id.uuidString
        record["membershipID"] = attendance.membership.id.uuidString
        record["attended"] = attendance.attended
        record["recordedAt"] = attendance.recordedAt
        save(record)
    }

    func pushTournament(_ tournament: Tournament) {
        let record = CKRecord(recordType: "Tournament", recordID: recordID(tournament.id))
        record["name"] = tournament.name
        record["sport"] = tournament.sport
        record["venue"] = tournament.venue
        record["startDate"] = tournament.startDate
        record["endDate"] = tournament.endDate
        record["maxTeams"] = tournament.maxTeams
        record["status"] = tournament.status
        record["notes"] = tournament.notes
        record["createdAt"] = tournament.createdAt
        record["teamIDs"] = tournament.teams.map { $0.id.uuidString }
        save(record)
    }

    func pushTournamentAttendance(_ attendance: TournamentAttendance) {
        let record = CKRecord(recordType: "TournamentAttendance", recordID: recordID(attendance.id))
        record["tournamentID"] = attendance.tournament.id.uuidString
        record["membershipID"] = attendance.membership.id.uuidString
        record["attended"] = attendance.attended
        record["recordedAt"] = attendance.recordedAt
        save(record)
    }

    func pushParticipation(_ participation: EventParticipation) {
        let record = CKRecord(recordType: "EventParticipation", recordID: recordID(participation.id))
        record["userID"] = participation.user.id.uuidString
        record["eventID"] = participation.event.id.uuidString
        record["status"] = participation.status
        record["registeredAt"] = participation.registeredAt
        save(record)
    }

    func pushUserIdentity(_ user: User) {
        let record = CKRecord(recordType: "UserIdentity", recordID: recordID(user.id))
        record["username"] = user.username
        record["displayName"] = user.displayName
        record["role"] = user.role
        record["isGrazerVSCMember"] = user.isGrazerVSCMember
        record["isRoot"] = user.isRoot
        save(record)
    }

    func pushClubMember(_ member: ClubMember) {
        let record = CKRecord(recordType: "ClubMember", recordID: recordID(member.id))
        record["firstName"] = member.firstName
        record["lastName"] = member.lastName
        record["address"] = member.address
        record["email"] = member.email
        record["phone"] = member.phone
        record["memberNumber"] = member.memberNumber
        record["joinedAt"] = member.joinedAt
        record["notes"] = member.notes
        save(record)
    }

    func deleteClubMember(_ id: UUID) {
        Task {
            do {
                try await publicDB.deleteRecord(withID: recordID(id))
            } catch {
                print("CloudKitSync delete failed for ClubMember \(id): \(error)")
            }
        }
    }

    /// Images are stored as a CKAsset (a file reference), not a raw Data field,
    /// since CloudKit expects large binaries to go through assets. That means
    /// staging the bytes to a temp file before the CKRecord save and cleaning
    /// it up afterward, unlike every other push here.
    func pushEventImage(_ image: EventImage) {
        let record = CKRecord(recordType: "EventImage", recordID: recordID(image.id))
        record["uploadedBy"] = image.uploadedBy
        record["uploadedAt"] = image.uploadedAt
        record["eventID"] = image.event?.id.uuidString
        record["trainingID"] = image.training?.id.uuidString
        record["tournamentID"] = image.tournament?.id.uuidString

        let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(image.id.uuidString).jpg")
        do {
            try image.imageData.write(to: tmpURL)
        } catch {
            print("CloudKitSync failed to stage image asset for \(image.id): \(error)")
            return
        }
        record["asset"] = CKAsset(fileURL: tmpURL)

        Task {
            defer { try? FileManager.default.removeItem(at: tmpURL) }
            do {
                _ = try await publicDB.save(record)
            } catch {
                print("CloudKitSync push failed for EventImage \(record.recordID.recordName): \(error)")
            }
        }
    }

    func deleteEventImage(_ id: UUID) {
        Task {
            do {
                try await publicDB.deleteRecord(withID: recordID(id))
            } catch {
                print("CloudKitSync delete failed for EventImage \(id): \(error)")
            }
        }
    }

    private func recordID(_ id: UUID) -> CKRecord.ID {
        CKRecord.ID(recordName: id.uuidString)
    }

    private func save(_ record: CKRecord) {
        Task {
            do {
                _ = try await publicDB.save(record)
            } catch {
                print("CloudKitSync push failed for \(record.recordType) \(record.recordID.recordName): \(error)")
            }
        }
    }

    /// Cheap existence check used to decide whether a brand-new account should
    /// bootstrap itself as root (only the very first account, ever, should).
    /// On failure (offline, etc.) conservatively reports `true` so an account
    /// created without network access never self-grants root — if that ever
    /// blocks legitimate bootstrapping, RootCLI can grant root out-of-band.
    func hasAnyUserIdentity() async -> Bool {
        let query = CKQuery(recordType: "UserIdentity", predicate: NSPredicate(value: true))
        do {
            let (results, _) = try await publicDB.records(matching: query, resultsLimit: 1)
            return !results.isEmpty
        } catch {
            return true
        }
    }

    // MARK: - Pull

    func syncAll(modelContext: ModelContext) async {
        await pullUserIdentities(modelContext: modelContext)
        await pullClubMembers(modelContext: modelContext)
        await pullTeams(modelContext: modelContext)
        await pullMemberships(modelContext: modelContext)
        await pullEvents(modelContext: modelContext)
        await pullTrainings(modelContext: modelContext)
        await pullTournaments(modelContext: modelContext)
        await pullEventImages(modelContext: modelContext)
        await pullParticipations(modelContext: modelContext)
        await pullTrainingAttendances(modelContext: modelContext)
        await pullTournamentAttendances(modelContext: modelContext)
        try? modelContext.save()
    }

    private func fetchAll(recordType: String) async -> [CKRecord] {
        do {
            let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
            let (results, _) = try await publicDB.records(matching: query)
            return results.compactMap { try? $1.get() }
        } catch {
            print("CloudKitSync pull failed for \(recordType): \(error)")
            return []
        }
    }

    private func findTeam(_ id: UUID?, modelContext: ModelContext) -> Team? {
        guard let id else { return nil }
        var descriptor = FetchDescriptor<Team>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    private func findTeams(_ ids: [String], modelContext: ModelContext) -> [Team] {
        ids.compactMap { UUID(uuidString: $0) }
            .compactMap { findTeam($0, modelContext: modelContext) }
    }

    private func findUser(_ id: UUID, modelContext: ModelContext) -> User? {
        var descriptor = FetchDescriptor<User>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    private func findClubMember(_ id: UUID, modelContext: ModelContext) -> ClubMember? {
        var descriptor = FetchDescriptor<ClubMember>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    private func findEvent(_ id: UUID, modelContext: ModelContext) -> SportEvent? {
        var descriptor = FetchDescriptor<SportEvent>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    private func findTraining(_ id: UUID, modelContext: ModelContext) -> Training? {
        var descriptor = FetchDescriptor<Training>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    private func findTournament(_ id: UUID, modelContext: ModelContext) -> Tournament? {
        var descriptor = FetchDescriptor<Tournament>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    private func findMembership(_ id: UUID, modelContext: ModelContext) -> TeamMembership? {
        var descriptor = FetchDescriptor<TeamMembership>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    private func pullUserIdentities(modelContext: ModelContext) async {
        for record in await fetchAll(recordType: "UserIdentity") {
            guard let id = UUID(uuidString: record.recordID.recordName) else { continue }
            let username = record["username"] as? String ?? ""
            let displayName = record["displayName"] as? String ?? ""
            let role = record["role"] as? String ?? "member"
            let isGrazerVSCMember = record["isGrazerVSCMember"] as? Bool ?? false
            let isRoot = record["isRoot"] as? Bool ?? false

            var descriptor = FetchDescriptor<User>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            if let existing = try? modelContext.fetch(descriptor).first {
                // Local email/appleUserIdentifier are never published, so never overwritten here.
                existing.username = username
                existing.displayName = displayName
                existing.role = role
                existing.isGrazerVSCMember = isGrazerVSCMember
                existing.isRoot = isRoot
            } else {
                let user = User(id: id, username: username, email: "", displayName: displayName, role: role,
                                 isGrazerVSCMember: isGrazerVSCMember, isRoot: isRoot)
                modelContext.insert(user)
            }
        }
    }

    private func pullClubMembers(modelContext: ModelContext) async {
        for record in await fetchAll(recordType: "ClubMember") {
            guard let id = UUID(uuidString: record.recordID.recordName) else { continue }
            let firstName = record["firstName"] as? String ?? ""
            let lastName = record["lastName"] as? String ?? ""
            let address = record["address"] as? String ?? ""
            let email = record["email"] as? String ?? ""
            let phone = record["phone"] as? String ?? ""
            let memberNumber = record["memberNumber"] as? String ?? ""
            let joinedAt = record["joinedAt"] as? Date ?? .now
            let notes = record["notes"] as? String ?? ""

            var descriptor = FetchDescriptor<ClubMember>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            if let existing = try? modelContext.fetch(descriptor).first {
                existing.firstName = firstName
                existing.lastName = lastName
                existing.address = address
                existing.email = email
                existing.phone = phone
                existing.memberNumber = memberNumber
                existing.notes = notes
            } else {
                let member = ClubMember(id: id, firstName: firstName, lastName: lastName, address: address,
                                         email: email, phone: phone, memberNumber: memberNumber,
                                         joinedAt: joinedAt, notes: notes)
                modelContext.insert(member)
            }
        }
    }

    private func pullTeams(modelContext: ModelContext) async {
        for record in await fetchAll(recordType: "Team") {
            guard let id = UUID(uuidString: record.recordID.recordName) else { continue }
            let name = record["name"] as? String ?? ""
            let sport = record["sport"] as? String ?? ""
            let descriptionText = record["descriptionText"] as? String ?? ""
            let createdAt = record["createdAt"] as? Date ?? .now

            var descriptor = FetchDescriptor<Team>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            if let existing = try? modelContext.fetch(descriptor).first {
                existing.name = name
                existing.sport = sport
                existing.descriptionText = descriptionText
            } else {
                let team = Team(id: id, name: name, sport: sport, descriptionText: descriptionText, createdAt: createdAt)
                modelContext.insert(team)
            }
        }
    }

    private func pullMemberships(modelContext: ModelContext) async {
        for record in await fetchAll(recordType: "TeamMembership") {
            guard let id = UUID(uuidString: record.recordID.recordName),
                  let teamIDString = record["teamID"] as? String, let teamID = UUID(uuidString: teamIDString),
                  let team = findTeam(teamID, modelContext: modelContext) else { continue }
            let user = (record["userID"] as? String).flatMap { UUID(uuidString: $0) }
                .flatMap { findUser($0, modelContext: modelContext) }
            let clubMember = (record["clubMemberID"] as? String).flatMap { UUID(uuidString: $0) }
                .flatMap { findClubMember($0, modelContext: modelContext) }
            // Exactly one side must resolve — a membership with neither is orphaned data.
            guard user != nil || clubMember != nil else { continue }
            let role = record["role"] as? String ?? "player"
            let joinedAt = record["joinedAt"] as? Date ?? .now

            var descriptor = FetchDescriptor<TeamMembership>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            if let existing = try? modelContext.fetch(descriptor).first {
                existing.role = role
            } else {
                let membership = TeamMembership(id: id, user: user, clubMember: clubMember, team: team, role: role, joinedAt: joinedAt)
                modelContext.insert(membership)
            }
        }
    }

    private func pullEvents(modelContext: ModelContext) async {
        for record in await fetchAll(recordType: "SportEvent") {
            guard let id = UUID(uuidString: record.recordID.recordName) else { continue }
            let title = record["title"] as? String ?? ""
            let sport = record["sport"] as? String ?? ""
            let location = record["location"] as? String ?? ""
            let startDate = record["startDate"] as? Date ?? .now
            let endDate = record["endDate"] as? Date ?? .now
            let notes = record["notes"] as? String ?? ""
            let createdBy = record["createdBy"] as? String ?? ""
            let createdAt = record["createdAt"] as? Date ?? .now
            let teams = findTeams(record["teamIDs"] as? [String] ?? [], modelContext: modelContext)

            var descriptor = FetchDescriptor<SportEvent>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            if let existing = try? modelContext.fetch(descriptor).first {
                existing.title = title
                existing.sport = sport
                existing.location = location
                existing.startDate = startDate
                existing.endDate = endDate
                existing.notes = notes
                existing.teams = teams
            } else {
                let event = SportEvent(id: id, title: title, sport: sport, location: location,
                                       startDate: startDate, endDate: endDate, notes: notes,
                                       createdBy: createdBy, createdAt: createdAt, teams: teams)
                modelContext.insert(event)
            }
        }
    }

    private func pullTrainings(modelContext: ModelContext) async {
        for record in await fetchAll(recordType: "Training") {
            guard let id = UUID(uuidString: record.recordID.recordName) else { continue }
            let title = record["title"] as? String ?? ""
            let sport = record["sport"] as? String ?? ""
            let location = record["location"] as? String ?? ""
            let startDate = record["startDate"] as? Date ?? .now
            let durationMinutes = record["durationMinutes"] as? Int ?? 90
            let focusArea = record["focusArea"] as? String ?? ""
            let notes = record["notes"] as? String ?? ""
            let createdBy = record["createdBy"] as? String ?? ""
            let createdAt = record["createdAt"] as? Date ?? .now
            let teams = findTeams(record["teamIDs"] as? [String] ?? [], modelContext: modelContext)

            var descriptor = FetchDescriptor<Training>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            if let existing = try? modelContext.fetch(descriptor).first {
                existing.title = title
                existing.sport = sport
                existing.location = location
                existing.startDate = startDate
                existing.durationMinutes = durationMinutes
                existing.focusArea = focusArea
                existing.notes = notes
                existing.teams = teams
            } else {
                let training = Training(id: id, title: title, sport: sport, location: location,
                                         startDate: startDate, durationMinutes: durationMinutes,
                                         focusArea: focusArea, notes: notes, createdBy: createdBy,
                                         createdAt: createdAt, teams: teams)
                modelContext.insert(training)
            }
        }
    }

    private func pullTrainingAttendances(modelContext: ModelContext) async {
        for record in await fetchAll(recordType: "TrainingAttendance") {
            guard let id = UUID(uuidString: record.recordID.recordName),
                  let trainingIDString = record["trainingID"] as? String, let trainingID = UUID(uuidString: trainingIDString),
                  let training = findTraining(trainingID, modelContext: modelContext),
                  let membershipIDString = record["membershipID"] as? String, let membershipID = UUID(uuidString: membershipIDString),
                  let membership = findMembership(membershipID, modelContext: modelContext) else { continue }
            let attended = record["attended"] as? Bool ?? false
            let recordedAt = record["recordedAt"] as? Date ?? .now

            var descriptor = FetchDescriptor<TrainingAttendance>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            if let existing = try? modelContext.fetch(descriptor).first {
                existing.attended = attended
                existing.recordedAt = recordedAt
            } else {
                let attendance = TrainingAttendance(id: id, training: training, membership: membership,
                                                     attended: attended, recordedAt: recordedAt)
                modelContext.insert(attendance)
            }
        }
    }

    private func pullTournaments(modelContext: ModelContext) async {
        for record in await fetchAll(recordType: "Tournament") {
            guard let id = UUID(uuidString: record.recordID.recordName) else { continue }
            let name = record["name"] as? String ?? ""
            let sport = record["sport"] as? String ?? ""
            let venue = record["venue"] as? String ?? ""
            let startDate = record["startDate"] as? Date ?? .now
            let endDate = record["endDate"] as? Date ?? .now
            let maxTeams = record["maxTeams"] as? Int ?? 8
            let status = record["status"] as? String ?? "planned"
            let notes = record["notes"] as? String ?? ""
            let createdAt = record["createdAt"] as? Date ?? .now
            let teams = findTeams(record["teamIDs"] as? [String] ?? [], modelContext: modelContext)

            var descriptor = FetchDescriptor<Tournament>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            if let existing = try? modelContext.fetch(descriptor).first {
                existing.name = name
                existing.sport = sport
                existing.venue = venue
                existing.startDate = startDate
                existing.endDate = endDate
                existing.maxTeams = maxTeams
                existing.status = status
                existing.notes = notes
                existing.teams = teams
            } else {
                let tournament = Tournament(id: id, name: name, sport: sport, venue: venue,
                                             startDate: startDate, endDate: endDate, maxTeams: maxTeams,
                                             status: status, notes: notes, createdAt: createdAt, teams: teams)
                modelContext.insert(tournament)
            }
        }
    }

    private func pullTournamentAttendances(modelContext: ModelContext) async {
        for record in await fetchAll(recordType: "TournamentAttendance") {
            guard let id = UUID(uuidString: record.recordID.recordName),
                  let tournamentIDString = record["tournamentID"] as? String, let tournamentID = UUID(uuidString: tournamentIDString),
                  let tournament = findTournament(tournamentID, modelContext: modelContext),
                  let membershipIDString = record["membershipID"] as? String, let membershipID = UUID(uuidString: membershipIDString),
                  let membership = findMembership(membershipID, modelContext: modelContext) else { continue }
            let attended = record["attended"] as? Bool ?? false
            let recordedAt = record["recordedAt"] as? Date ?? .now

            var descriptor = FetchDescriptor<TournamentAttendance>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            if let existing = try? modelContext.fetch(descriptor).first {
                existing.attended = attended
                existing.recordedAt = recordedAt
            } else {
                let attendance = TournamentAttendance(id: id, tournament: tournament, membership: membership,
                                                       attended: attended, recordedAt: recordedAt)
                modelContext.insert(attendance)
            }
        }
    }

    private func pullEventImages(modelContext: ModelContext) async {
        for record in await fetchAll(recordType: "EventImage") {
            guard let id = UUID(uuidString: record.recordID.recordName) else { continue }

            // Images are immutable once uploaded, and CKAsset downloads aren't free —
            // skip straight past anything already local instead of re-fetching bytes.
            var existingDescriptor = FetchDescriptor<EventImage>(predicate: #Predicate { $0.id == id })
            existingDescriptor.fetchLimit = 1
            if (try? modelContext.fetch(existingDescriptor).first) != nil { continue }

            guard let asset = record["asset"] as? CKAsset,
                  let fileURL = asset.fileURL,
                  let data = try? Data(contentsOf: fileURL) else { continue }

            let uploadedBy = record["uploadedBy"] as? String ?? ""
            let uploadedAt = record["uploadedAt"] as? Date ?? .now
            let event = (record["eventID"] as? String).flatMap { UUID(uuidString: $0) }
                .flatMap { findEvent($0, modelContext: modelContext) }
            let training = (record["trainingID"] as? String).flatMap { UUID(uuidString: $0) }
                .flatMap { findTraining($0, modelContext: modelContext) }
            let tournament = (record["tournamentID"] as? String).flatMap { UUID(uuidString: $0) }
                .flatMap { findTournament($0, modelContext: modelContext) }

            let image = EventImage(id: id, imageData: data, uploadedBy: uploadedBy, uploadedAt: uploadedAt,
                                    event: event, training: training, tournament: tournament)
            modelContext.insert(image)
        }
    }

    private func pullParticipations(modelContext: ModelContext) async {
        for record in await fetchAll(recordType: "EventParticipation") {
            guard let id = UUID(uuidString: record.recordID.recordName),
                  let userIDString = record["userID"] as? String, let userID = UUID(uuidString: userIDString),
                  let eventIDString = record["eventID"] as? String, let eventID = UUID(uuidString: eventIDString),
                  let user = findUser(userID, modelContext: modelContext),
                  let event = findEvent(eventID, modelContext: modelContext) else { continue }
            let status = record["status"] as? String ?? "invited"
            let registeredAt = record["registeredAt"] as? Date ?? .now

            var descriptor = FetchDescriptor<EventParticipation>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            if let existing = try? modelContext.fetch(descriptor).first {
                existing.status = status
            } else {
                let participation = EventParticipation(id: id, user: user, event: event, status: status, registeredAt: registeredAt)
                modelContext.insert(participation)
            }
        }
    }
}
