import CloudKit
import SwiftData
import Foundation

/// Shares Team/Event/Training/Tournament/Membership/Participation/Member/
/// EventImage data across different users' Apple IDs via CloudKit's public
/// database.
/// SwiftData's own CloudKit integration only mirrors the private, per-user
/// database, so it can't do this — this layer pushes/pulls plain CKRecords
/// instead, matching local SwiftData objects by their stable `id` (used as
/// the CKRecord name).
///
/// Only non-sensitive identity fields (firstName, lastName, role,
/// isGrazerVSCMember) are ever published for a User — email and the Apple
/// identifier stay device-local. The Member roster (name/address/contact
/// details) is admin-managed data, synced so every admin's device and the
/// account-creation match check see the same roster. The CKRecord type
/// stays the historical "ClubMember" string (not renamed to "Member")
/// so already-synced production data keeps resolving after this
/// app-side rename — see cerebrum.md 2026-08-01.
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
        // Field key stays "clubMemberID" (not renamed) for wire compatibility
        // with already-synced production data — see the Member rename note above.
        record["clubMemberID"] = membership.member?.id.uuidString
        record["teamID"] = membership.team.id.uuidString
        record["role"] = membership.role
        record["joinedAt"] = membership.joinedAt
        save(record)
    }

    // Was missing entirely until bug-163: TeamsViews' roster swipe-to-delete
    // called modelContext.delete(membership) with no CloudKit counterpart, so
    // a "deleted" membership silently reappeared on the next pullMemberships
    // (find-or-create by id, see pullMemberships below) — and, combined with
    // TeamMembership lacking a cascade rule for its Attendance records at the
    // time, corrupted the local store outright (see the TeamMembership.
    // attendances doc comment in Models.swift).
    func deleteMembership(_ id: UUID) {
        Task {
            do {
                try await publicDB.deleteRecord(withID: recordID(id))
            } catch {
                print("CloudKitSync delete failed for TeamMembership \(id): \(error)")
            }
        }
    }

    // Same gap as deleteMembership above, for Team's own delete path
    // (TeamsListView.deleteTeams) — was also never pushed.
    func deleteTeam(_ id: UUID) {
        Task {
            do {
                try await publicDB.deleteRecord(withID: recordID(id))
            } catch {
                print("CloudKitSync delete failed for Team \(id): \(error)")
            }
        }
    }

    func pushEvent(_ event: SportEvent) {
        let record = CKRecord(recordType: "SportEvent", recordID: recordID(event.id))
        record["title"] = event.title
        record["sport"] = event.sport
        record["location"] = event.location
        record["street"] = event.street
        record["zip"] = event.zip
        record["city"] = event.city
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
        record["street"] = training.street
        record["zip"] = training.zip
        record["city"] = training.city
        record["startDate"] = training.startDate
        record["endDate"] = training.endDate
        record["durationMinutes"] = training.durationMinutes
        record["focusArea"] = training.focusArea
        record["notes"] = training.notes
        record["createdBy"] = training.createdBy
        record["createdAt"] = training.createdAt
        record["teamIDs"] = training.teams.map { $0.id.uuidString }
        save(record)
    }

    /// Shared by Training and Tournament attendance (both now backed by the
    /// single local `Attendance` model) — keeps the two existing CKRecord
    /// types ("TrainingAttendance"/"TournamentAttendance") for backward
    /// compatibility with already-synced data, picking the type via
    /// `attendance.event.kind` rather than introducing a new unified record
    /// type that old data wouldn't be found under.
    func pushAttendance(_ attendance: Attendance) {
        let recordType = attendance.event.kind == "tournament" ? "TournamentAttendance" : "TrainingAttendance"
        let record = CKRecord(recordType: recordType, recordID: recordID(attendance.id))
        record["trainingID"] = attendance.event.kind == "tournament" ? nil : attendance.event.id.uuidString
        record["tournamentID"] = attendance.event.kind == "tournament" ? attendance.event.id.uuidString : nil
        record["membershipID"] = attendance.membership.id.uuidString
        record["attended"] = attendance.attended
        record["recordedAt"] = attendance.recordedAt
        record["praeAmount"] = attendance.praeAmount
        save(record)
    }

    /// Writes both the new (`title`/`location`) and old (`name`/`venue`) field
    /// names for one release cycle, so a still-updating old client editing the
    /// same record doesn't clobber the new fields with stale data mid-rollout.
    func pushTournament(_ tournament: Tournament) {
        let record = CKRecord(recordType: "Tournament", recordID: recordID(tournament.id))
        record["title"] = tournament.title
        record["name"] = tournament.title
        record["sport"] = tournament.sport
        record["location"] = tournament.location
        record["venue"] = tournament.location
        record["street"] = tournament.street
        record["zip"] = tournament.zip
        record["city"] = tournament.city
        record["startDate"] = tournament.startDate
        record["endDate"] = tournament.endDate
        record["maxTeams"] = tournament.maxTeams
        record["status"] = tournament.status
        record["notes"] = tournament.notes
        record["createdBy"] = tournament.createdBy
        record["createdAt"] = tournament.createdAt
        record["teamIDs"] = tournament.teams.map { $0.id.uuidString }
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
        record["firstName"] = user.firstName
        record["lastName"] = user.lastName
        record["role"] = user.role
        record["isGrazerVSCMember"] = user.isGrazerVSCMember
        record["isRoot"] = user.isRoot
        save(record)
    }

    func deleteUserIdentity(_ id: UUID) {
        Task {
            do {
                try await publicDB.deleteRecord(withID: recordID(id))
            } catch {
                print("CloudKitSync delete failed for UserIdentity \(id): \(error)")
            }
        }
    }

    func pushMember(_ member: Member) {
        // recordType stays the historical "ClubMember" string — see the
        // Member rename note in this file's top doc comment.
        let record = CKRecord(recordType: "ClubMember", recordID: recordID(member.id))
        record["firstName"] = member.firstName
        record["lastName"] = member.lastName
        record["street"] = member.street
        record["zip"] = member.zip
        record["city"] = member.city
        record["email"] = member.email
        record["phone"] = member.phone
        record["memberNumber"] = member.memberNumber
        record["joinedAt"] = member.joinedAt
        record["notes"] = member.notes
        record["gender"] = member.gender
        record["title"] = member.title
        record["birthDate"] = member.birthDate
        record["sportId"] = member.sportId
        record["svnr"] = member.svnr
        record["iban"] = member.iban
        record["lastMedicalExamination"] = member.lastMedicalExamination
        record["defaultFunction"] = member.defaultFunction
        record["memberOfGVSC"] = member.memberOfGVSC
        save(record)
    }

    func deleteMember(_ id: UUID) {
        Task {
            do {
                try await publicDB.deleteRecord(withID: recordID(id))
            } catch {
                print("CloudKitSync delete failed for Member \(id): \(error)")
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
                try await upsert(record)
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
                try await upsert(record)
            } catch {
                print("CloudKitSync push failed for \(record.recordType) \(record.recordID.recordName): \(error)")
            }
        }
    }

    /// Every push here builds a brand-new `CKRecord` instance rather than
    /// fetching the existing one first, so it never carries a
    /// `recordChangeTag`. `CKDatabase.save(_:)`'s default save policy
    /// (`.ifServerRecordUnchanged`) treats that as an unverifiable conflict
    /// and throws `CKError.serverRecordChanged` on any push after the first
    /// (i.e. inserts work, updates silently fail). Using
    /// `CKModifyRecordsOperation` with `.changedKeys` instead makes this a
    /// true insert-or-update: it always writes the fields present on the
    /// record, whether or not a server copy already exists.
    private func upsert(_ record: CKRecord) async throws {
        try await withCheckedThrowingContinuation { continuation in
            let operation = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
            operation.savePolicy = .changedKeys
            operation.qualityOfService = .userInitiated
            operation.modifyRecordsResultBlock = { result in
                continuation.resume(with: result)
            }
            publicDB.add(operation)
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

    /// Ensures a `CKQuerySubscription` exists for `user`'s current team
    /// memberships, for both Training and Tournament creation — so members
    /// of those teams get a native push notification when one is created,
    /// including on a device where the app isn't running at all (see
    /// `PushNotifications.swift`'s doc comment for why this uses plain
    /// "alert" subscriptions instead of a silent-push +
    /// client-constructed-notification pattern).
    ///
    /// One subscription per (user, record type) — NOT per team — with an
    /// `ANY teamIDs IN %@` predicate against the user's full current set of
    /// team ids, re-saved with the same deterministic `subscriptionID`
    /// (`"training-created-<user.id>"`) every time this runs. Saving over an
    /// existing subscription ID replaces its predicate, so this naturally
    /// keeps the subscription in sync with team joins/leaves — no separate
    /// cleanup logic needed, unlike a per-team subscription scheme would
    /// require. A subscriptionID keyed by this app's own stable `user.id`
    /// (not a per-device id) is deliberate: the same person using the app on
    /// two devices under the same iCloud account should update the SAME
    /// subscription, not create a second one — CloudKit already delivers a
    /// subscription's pushes to every device registered under that account
    /// for this container, so there's no need for a per-device identity here.
    /// No-op if the user currently has no team memberships at all.
    func ensureTrainingTournamentSubscriptions(for user: User) async {
        let teamIDStrings = user.memberships.map { $0.team.id.uuidString }
        guard !teamIDStrings.isEmpty else { return }
        await ensureCreationSubscription(recordType: "Training", teamIDStrings: teamIDStrings,
                                          titleKey: "training_created_title", bodyKey: "training_created_body",
                                          subscriptionID: "training-created-\(user.id.uuidString)")
        await ensureCreationSubscription(recordType: "Tournament", teamIDStrings: teamIDStrings,
                                          titleKey: "tournament_created_title", bodyKey: "tournament_created_body",
                                          subscriptionID: "tournament-created-\(user.id.uuidString)")
    }

    /// Alert text is resolved by iOS itself at display time from
    /// `Localizable.xcstrings` via `titleLocalizationKey`/
    /// `alertLocalizationKey`, with `alertLocalizationArgs` naming the
    /// pushed record's OWN field keys ("title"/"location") to substitute
    /// into that localized format string's `%1$@`/`%2$@` placeholders — no
    /// app code runs to construct this, which is what makes it work even
    /// when the recipient's app is fully terminated.
    private func ensureCreationSubscription(recordType: String, teamIDStrings: [String],
                                             titleKey: String, bodyKey: String, subscriptionID: String) async {
        let predicate = NSPredicate(format: "ANY teamIDs IN %@", teamIDStrings)
        let subscription = CKQuerySubscription(recordType: recordType, predicate: predicate,
                                                subscriptionID: subscriptionID,
                                                options: .firesOnRecordCreation)
        let info = CKSubscription.NotificationInfo()
        info.titleLocalizationKey = titleKey
        info.alertLocalizationKey = bodyKey
        info.alertLocalizationArgs = ["title", "location"]
        info.soundName = "default"
        info.shouldBadge = true
        subscription.notificationInfo = info
        do {
            try await publicDB.save(subscription)
        } catch {
            print("CloudKitSync failed to save subscription \(subscriptionID): \(error)")
        }
    }

    /// Creates and pushes any of `Team.defaultTeams` not already present in
    /// the LOCAL store (case-insensitive name match), so the club's standing
    /// teams exist automatically — a no-op once all four exist. Called once
    /// per launch from RootView.triggerBackgroundSync (right after syncAll)
    /// and again from TeamsListView's pull-to-refresh.
    ///
    /// Deliberately checks the local store, NOT a live CloudKit query —
    /// `syncAll` just ran immediately before every call site, so the local
    /// store already reflects the latest known remote state. An earlier
    /// version gated local creation behind its own live CKQuery and bailed
    /// out entirely (creating nothing, not even locally) if that query
    /// failed — which meant the whole feature silently never worked if
    /// CloudKit was unreachable/unauthenticated for any reason on a given
    /// device, regardless of retries (see bug-186 in buglog.json). Local
    /// team creation doesn't actually need CloudKit at all; only `pushTeam`
    /// below does, and it already fails silently/independently like every
    /// other push in this app if the network isn't there. The tradeoff is a
    /// narrow re-opened race (two devices seeding simultaneously, before
    /// either has pushed, could each create a duplicate) — accepted as a
    /// better tradeoff than a feature that doesn't reliably work at all for
    /// this single-club, at-most-a-few-admin-devices app.
    func ensureDefaultTeams(modelContext: ModelContext) async {
        let existingTeams = (try? modelContext.fetch(FetchDescriptor<Team>())) ?? []

        // One-time rename: the original sport-agnostic "Helfer" default team
        // was split into "Torball Helfer"/"Blindenfußball Helfer" (see
        // Team.defaultTeams). Renaming any already-created "Helfer" team in
        // place (same id, same memberships, still pushed under the same
        // CKRecord name) rather than leaving it orphaned and creating a
        // brand-new "Torball Helfer" team alongside it.
        if let legacyHelfer = existingTeams.first(where: {
            $0.name.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare("Helfer") == .orderedSame
        }) {
            legacyHelfer.name = "Torball Helfer"
            legacyHelfer.sport = "Torball"
            pushTeam(legacyHelfer)
        }

        let existingNames = Set(existingTeams.map { $0.name.trimmingCharacters(in: .whitespaces).lowercased() })
        for (name, sport) in Team.defaultTeams {
            guard !existingNames.contains(name.trimmingCharacters(in: .whitespaces).lowercased()) else { continue }
            let team = Team(name: name, sport: sport)
            modelContext.insert(team)
            pushTeam(team)
        }
        try? modelContext.save()
    }

    // MARK: - Pull

    func syncAll(modelContext: ModelContext) async {
        await pullUserIdentities(modelContext: modelContext)
        await pullMembers(modelContext: modelContext)
        await pullTeams(modelContext: modelContext)
        await pullMemberships(modelContext: modelContext)
        await pullEvents(modelContext: modelContext)
        await pullTrainings(modelContext: modelContext)
        await pullTournaments(modelContext: modelContext)
        await pullEventImages(modelContext: modelContext)
        await pullParticipations(modelContext: modelContext)
        await pullAttendances(modelContext: modelContext)
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

    private func findMember(_ id: UUID, modelContext: ModelContext) -> Member? {
        var descriptor = FetchDescriptor<Member>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    /// SportEvent is polymorphically fetchable — this resolves a Training or
    /// Tournament id just as well as a plain SportEvent id, since they're all
    /// the same underlying type hierarchy now.
    private func findEvent(_ id: UUID, modelContext: ModelContext) -> SportEvent? {
        var descriptor = FetchDescriptor<SportEvent>(predicate: #Predicate { $0.id == id })
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
            let firstName = record["firstName"] as? String ?? ""
            let lastName = record["lastName"] as? String ?? ""
            let role = record["role"] as? String ?? "member"
            let isGrazerVSCMember = record["isGrazerVSCMember"] as? Bool ?? false
            let isRoot = record["isRoot"] as? Bool ?? false

            var descriptor = FetchDescriptor<User>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            if let existing = try? modelContext.fetch(descriptor).first {
                // Local email/appleUserIdentifier are never published, so never overwritten here.
                existing.firstName = firstName
                existing.lastName = lastName
                existing.role = role
                existing.isGrazerVSCMember = isGrazerVSCMember
                existing.isRoot = isRoot
            } else {
                let user = User(id: id, email: "", firstName: firstName, lastName: lastName,
                                 role: role, isGrazerVSCMember: isGrazerVSCMember, isRoot: isRoot)
                modelContext.insert(user)
            }
        }
    }

    private func pullMembers(modelContext: ModelContext) async {
        // recordType stays the historical "ClubMember" string — see this
        // file's top doc comment.
        for record in await fetchAll(recordType: "ClubMember") {
            guard let id = UUID(uuidString: record.recordID.recordName) else { continue }
            let firstName = record["firstName"] as? String ?? ""
            let lastName = record["lastName"] as? String ?? ""
            let street = record["street"] as? String ?? ""
            let zip = record["zip"] as? String ?? ""
            let city = record["city"] as? String ?? ""
            let email = record["email"] as? String ?? ""
            let phone = record["phone"] as? String ?? ""
            let memberNumber = record["memberNumber"] as? String ?? ""
            let joinedAt = record["joinedAt"] as? Date ?? .now
            let notes = record["notes"] as? String ?? ""
            let gender = record["gender"] as? String ?? ""
            let title = record["title"] as? String ?? ""
            let birthDate = record["birthDate"] as? Date
            let sportId = record["sportId"] as? String ?? ""
            let svnr = record["svnr"] as? String ?? ""
            let iban = record["iban"] as? String ?? ""
            let lastMedicalExamination = record["lastMedicalExamination"] as? Date
            let defaultFunction = record["defaultFunction"] as? String ?? ""
            // Missing on records pushed before this flag existed — default true,
            // matching every pre-existing roster entry's implicit membership.
            let memberOfGVSC = record["memberOfGVSC"] as? Bool ?? true

            var descriptor = FetchDescriptor<Member>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            if let existing = try? modelContext.fetch(descriptor).first {
                existing.firstName = firstName
                existing.lastName = lastName
                existing.street = street
                existing.zip = zip
                existing.city = city
                existing.email = email
                existing.phone = phone
                existing.memberNumber = memberNumber
                existing.notes = notes
                existing.gender = gender
                existing.title = title
                existing.birthDate = birthDate
                existing.sportId = sportId
                existing.svnr = svnr
                existing.iban = iban
                existing.lastMedicalExamination = lastMedicalExamination
                existing.defaultFunction = defaultFunction
                existing.memberOfGVSC = memberOfGVSC
            } else {
                let member = Member(id: id, firstName: firstName, lastName: lastName, street: street,
                                     zip: zip, city: city, email: email, phone: phone,
                                     memberNumber: memberNumber, joinedAt: joinedAt, notes: notes,
                                     gender: gender, title: title, birthDate: birthDate, sportId: sportId,
                                     svnr: svnr, iban: iban, lastMedicalExamination: lastMedicalExamination,
                                     defaultFunction: defaultFunction, memberOfGVSC: memberOfGVSC)
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
            // Field key stays "clubMemberID" on the wire — see this file's top doc comment.
            let member = (record["clubMemberID"] as? String).flatMap { UUID(uuidString: $0) }
                .flatMap { findMember($0, modelContext: modelContext) }
            // Exactly one side must resolve — a membership with neither is orphaned data.
            guard user != nil || member != nil else { continue }
            let role = record["role"] as? String ?? "player"
            let joinedAt = record["joinedAt"] as? Date ?? .now

            var descriptor = FetchDescriptor<TeamMembership>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            if let existing = try? modelContext.fetch(descriptor).first {
                existing.role = role
            } else {
                let membership = TeamMembership(id: id, user: user, member: member, team: team, role: role, joinedAt: joinedAt)
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
            let street = record["street"] as? String ?? ""
            let zip = record["zip"] as? String ?? ""
            let city = record["city"] as? String ?? ""
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
                existing.street = street
                existing.zip = zip
                existing.city = city
                existing.startDate = startDate
                existing.endDate = endDate
                existing.notes = notes
                existing.teams = teams
            } else {
                let event = SportEvent(id: id, title: title, sport: sport, location: location,
                                       street: street, zip: zip, city: city,
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
            let street = record["street"] as? String ?? ""
            let zip = record["zip"] as? String ?? ""
            let city = record["city"] as? String ?? ""
            let startDate = record["startDate"] as? Date ?? .now
            let endDate = record["endDate"] as? Date ?? startDate
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
                existing.street = street
                existing.zip = zip
                existing.city = city
                existing.startDate = startDate
                existing.endDate = endDate
                existing.durationMinutes = durationMinutes
                existing.focusArea = focusArea
                existing.notes = notes
                existing.teams = teams
            } else {
                let training = Training(id: id, title: title, sport: sport, location: location,
                                         street: street, zip: zip, city: city,
                                         startDate: startDate, durationMinutes: durationMinutes,
                                         focusArea: focusArea, notes: notes, createdBy: createdBy,
                                         createdAt: createdAt, teams: teams)
                training.endDate = endDate
                modelContext.insert(training)
            }
        }
    }

    /// Pulls both CKRecord types ("TrainingAttendance"/"TournamentAttendance",
    /// kept distinct for backward compatibility — see pushAttendance) into the
    /// single local `Attendance` model, resolving `event` via the now-generic
    /// `findEvent`.
    private func pullAttendances(modelContext: ModelContext) async {
        for recordType in ["TrainingAttendance", "TournamentAttendance"] {
            let eventIDField = recordType == "TournamentAttendance" ? "tournamentID" : "trainingID"
            for record in await fetchAll(recordType: recordType) {
                guard let id = UUID(uuidString: record.recordID.recordName),
                      let eventIDString = record[eventIDField] as? String, let eventID = UUID(uuidString: eventIDString),
                      let event = findEvent(eventID, modelContext: modelContext),
                      let membershipIDString = record["membershipID"] as? String, let membershipID = UUID(uuidString: membershipIDString),
                      let membership = findMembership(membershipID, modelContext: modelContext) else { continue }
                let attended = record["attended"] as? Bool ?? false
                let recordedAt = record["recordedAt"] as? Date ?? .now
                let praeAmount = record["praeAmount"] as? Double

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

    private func pullTournaments(modelContext: ModelContext) async {
        for record in await fetchAll(recordType: "Tournament") {
            guard let id = UUID(uuidString: record.recordID.recordName) else { continue }
            let title = (record["title"] as? String) ?? (record["name"] as? String) ?? ""
            let sport = record["sport"] as? String ?? ""
            let location = (record["location"] as? String) ?? (record["venue"] as? String) ?? ""
            let street = record["street"] as? String ?? ""
            let zip = record["zip"] as? String ?? ""
            let city = record["city"] as? String ?? ""
            let startDate = record["startDate"] as? Date ?? .now
            let endDate = record["endDate"] as? Date ?? .now
            let maxTeams = record["maxTeams"] as? Int ?? 8
            let status = record["status"] as? String ?? "planned"
            let notes = record["notes"] as? String ?? ""
            let createdBy = record["createdBy"] as? String ?? ""
            let createdAt = record["createdAt"] as? Date ?? .now
            let teams = findTeams(record["teamIDs"] as? [String] ?? [], modelContext: modelContext)

            var descriptor = FetchDescriptor<Tournament>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            if let existing = try? modelContext.fetch(descriptor).first {
                existing.title = title
                existing.sport = sport
                existing.location = location
                existing.street = street
                existing.zip = zip
                existing.city = city
                existing.startDate = startDate
                existing.endDate = endDate
                existing.maxTeams = maxTeams
                existing.status = status
                existing.notes = notes
                existing.teams = teams
            } else {
                let tournament = Tournament(id: id, title: title, sport: sport, location: location,
                                             street: street, zip: zip, city: city,
                                             startDate: startDate, endDate: endDate, maxTeams: maxTeams,
                                             status: status, notes: notes, createdBy: createdBy,
                                             createdAt: createdAt, teams: teams)
                modelContext.insert(tournament)
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
            // New records only carry eventID; pre-refactor records carried the
            // FK under trainingID/tournamentID instead — fall back to those so
            // a device syncing for the first time after this change still
            // resolves images uploaded before it.
            let eventIDString = (record["eventID"] as? String)
                ?? (record["trainingID"] as? String)
                ?? (record["tournamentID"] as? String)
            let event = eventIDString.flatMap { UUID(uuidString: $0) }
                .flatMap { findEvent($0, modelContext: modelContext) }

            let image = EventImage(id: id, imageData: data, uploadedBy: uploadedBy, uploadedAt: uploadedAt,
                                    event: event)
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
