import Foundation
import Supabase
import SwiftData

// Push and pull per table. Pulls fetch rows changed since the table's cursor;
// with no cursor (first sync, or a new access signature) they fetch
// everything and also remove local rows the server didn't return.

extension SupabaseSync {
    /// Fetch, apply, advance the cursor; prune on a full pull.
    private func pull<Row: Decodable & Sendable, Model: PersistentModel>(
        _ table: String, columns: String = "*", modelContext: ModelContext,
        prune model: Model.Type, id modelID: (Model) -> UUID, pruneMissing: Bool = true,
        rowID: (Row) -> UUID, updatedAt: (Row) -> Date?, apply: (Row) -> Void
    ) async throws {
        let since = cursor(table)
        let rows: [Row] = try await fetchChanged(table, since: since, columns: columns)
        for row in rows { apply(row) }
        if since == nil, pruneMissing {
            let keep = Set(rows.map(rowID))
            for object in (try? modelContext.fetch(FetchDescriptor<Model>())) ?? []
            where !keep.contains(modelID(object)) && !hasPendingPush(modelID(object)) {
                modelContext.delete(object)
            }
        }
        setCursor(table, rows.compactMap(updatedAt).max())
    }

    // MARK: - Teams

    func pushTeam(_ team: Team) { save(TeamDBRow(team), table: "teams", id: team.id) }
    func deleteTeam(_ id: UUID) { delete(table: "teams", id: id) }

    func pullTeams(modelContext: ModelContext) async throws {
        try await pull("teams", modelContext: modelContext, prune: Team.self, id: \.id,
                       rowID: { (row: TeamDBRow) in row.id }, updatedAt: \.updatedAt) { row in
            if let team = findTeam(row.id, modelContext: modelContext) {
                team.name = row.name
                team.sport = row.sport
                team.descriptionText = row.descriptionText
            } else {
                modelContext.insert(Team(id: row.id, name: row.name, sport: row.sport,
                                         descriptionText: row.descriptionText, createdAt: row.createdAt))
            }
        }
    }

    /// Creates any missing `Team.defaultTeams` (by name) — only for accounts
    /// that may manage teams; the server's unique name index stops two
    /// devices from creating the same team twice.
    func ensureDefaultTeams(modelContext: ModelContext) async {
        guard AuthContext.current?.can(.teamsManage) == true else { return }
        let existing = Set(((try? modelContext.fetch(FetchDescriptor<Team>())) ?? [])
            .map { $0.name.trimmingCharacters(in: .whitespaces).lowercased() })
        for (name, sport) in Team.defaultTeams
        where !existing.contains(name.trimmingCharacters(in: .whitespaces).lowercased()) {
            let team = Team(name: name, sport: sport)
            modelContext.insert(team)
            pushTeam(team)
        }
        try? modelContext.save()
    }

    // MARK: - Team memberships

    func pushMembership(_ membership: TeamMembership) {
        save(TeamMembershipDBRow(membership), table: "team_memberships", id: membership.id)
    }
    func deleteMembership(_ id: UUID) { delete(table: "team_memberships", id: id) }

    func pullMemberships(modelContext: ModelContext) async throws {
        try await pull("team_memberships", modelContext: modelContext, prune: TeamMembership.self, id: \.id,
                       rowID: { (row: TeamMembershipDBRow) in row.id }, updatedAt: \.updatedAt) { row in
            guard let team = findTeam(row.teamID, modelContext: modelContext) else { return }
            let user = row.userID.flatMap { findUser($0, modelContext: modelContext) }
            let member = row.memberID.flatMap { findMember($0, modelContext: modelContext) }
            let role = MembershipRole.normalize(row.role)
            if let existing = findMembership(row.id, modelContext: modelContext) {
                existing.role = role
                existing.team = team
                existing.member = member
                existing.user = user
            } else {
                guard user != nil || member != nil else { return }
                modelContext.insert(TeamMembership(id: row.id, user: user, member: member, team: team,
                                                   role: role, joinedAt: row.joinedAt))
            }
        }
    }

    // MARK: - Roster

    /// Names to `members`, contact details to `member_contacts`; the
    /// protected fields go through `MemberPrivateSync` (member_private).
    func pushMember(_ member: Member) {
        save(MemberDBRow(member), table: "members", id: member.id)
        // Only accounts that may see contacts send them — anyone else would
        // overwrite them with the blanks their cache holds.
        if AuthContext.current?.can(.membersManage) == true {
            save(MemberContactDBRow(member), table: "member_contacts", id: member.id)
        }
    }

    func deleteMember(_ id: UUID) { delete(table: "members", id: id) }

    func pullMembers(modelContext: ModelContext) async throws {
        try await pull("members", modelContext: modelContext, prune: Member.self, id: \.id,
                       rowID: { (row: MemberDBRow) in row.id }, updatedAt: \.updatedAt) { row in
            if let member = findMember(row.id, modelContext: modelContext) {
                member.firstName = row.firstName
                member.lastName = row.lastName
                member.memberNumber = row.memberNumber
                member.sportId = row.sportID
                member.defaultFunction = row.defaultFunction
                member.memberOfGVSC = row.memberOfGVSC
                member.joinedAt = row.joinedAt
            } else {
                modelContext.insert(Member(id: row.id, firstName: row.firstName, lastName: row.lastName,
                                           street: "", zip: "", city: "", country: "", email: "", phone: "",
                                           memberNumber: row.memberNumber, joinedAt: row.joinedAt, notes: "",
                                           gender: "", title: "", birthDate: nil, sportId: row.sportID,
                                           svnr: "", iban: "", lastMedicalExamination: nil,
                                           defaultFunction: row.defaultFunction, memberOfGVSC: row.memberOfGVSC))
            }
        }
        try modelContext.save()
        try await pullMemberContacts(modelContext: modelContext)
    }

    /// RLS returns all contacts for members.manage, otherwise only the
    /// account's own entry. On a full pull, contacts this account may no
    /// longer read are blanked.
    private func pullMemberContacts(modelContext: ModelContext) async throws {
        let table = "member_contacts"
        let since = cursor(table)
        let rows: [MemberContactDBRow] = try await fetchChanged(table, since: since)
        for row in rows {
            guard let member = findMember(row.id, modelContext: modelContext) else { continue }
            member.street = row.street
            member.zip = row.zip
            member.city = row.city
            member.country = row.country
            member.email = row.email
            member.phone = row.phone
            member.notes = row.notes
            member.gender = row.gender
            member.title = row.title
        }
        if since == nil {
            let readable = Set(rows.map(\.id))
            for member in (try? modelContext.fetch(FetchDescriptor<Member>())) ?? []
            where !readable.contains(member.id) && !hasPendingPush(member.id) {
                member.street = ""; member.zip = ""; member.city = ""; member.country = ""
                member.email = ""; member.phone = ""; member.notes = ""; member.gender = ""; member.title = ""
            }
        }
        setCursor(table, rows.compactMap(\.updatedAt).max())
    }

    // MARK: - Events (SportEvent / Training / Tournament)

    func pushEvent(_ event: SportEvent) { save(EventDBRow(event), table: "events", id: event.id) }
    func pushTraining(_ training: Training) { pushEvent(training) }
    func pushTournament(_ tournament: Tournament) { pushEvent(tournament) }
    func deleteEvent(_ id: UUID) { delete(table: "events", id: id) }

    func pullEvents(modelContext: ModelContext) async throws {
        try await pull("events", modelContext: modelContext, prune: SportEvent.self, id: \.id,
                       rowID: { (row: EventDBRow) in row.id }, updatedAt: \.updatedAt) { row in
            apply(row, modelContext: modelContext)
        }
    }

    private func apply(_ row: EventDBRow, modelContext: ModelContext) {
        let teams = findTeams(row.teamIDs, modelContext: modelContext)
        let event: SportEvent
        if let existing = findEvent(row.id, modelContext: modelContext) {
            event = existing
        } else {
            switch row.kind {
            case "training":
                event = Training(id: row.id, title: row.title, sport: row.sport, location: row.location,
                                 street: row.street, zip: row.zip, city: row.city, country: row.country,
                                 startDate: row.startDate, durationMinutes: row.durationMinutes ?? 90,
                                 focusArea: row.focusArea ?? "", status: row.status.isEmpty ? Training.openStatus : row.status,
                                 notes: row.notes, createdBy: row.createdBy, createdAt: row.createdAt, teams: teams)
            case "tournament":
                event = Tournament(id: row.id, title: row.title, sport: row.sport, location: row.location,
                                   street: row.street, zip: row.zip, city: row.city, country: row.country,
                                   startDate: row.startDate, endDate: row.endDate, maxTeams: row.maxTeams ?? 8,
                                   status: row.status.isEmpty ? "planned" : row.status, notes: row.notes,
                                   createdBy: row.createdBy, createdAt: row.createdAt, teams: teams)
            default:
                event = SportEvent(id: row.id, title: row.title, sport: row.sport, location: row.location,
                                   street: row.street, zip: row.zip, city: row.city, country: row.country,
                                   startDate: row.startDate, endDate: row.endDate, notes: row.notes,
                                   createdBy: row.createdBy, createdAt: row.createdAt, teams: teams)
            }
            modelContext.insert(event)
        }
        event.title = row.title
        event.sport = row.sport
        event.location = row.location
        event.street = row.street
        event.zip = row.zip
        event.city = row.city
        event.country = row.country
        event.startDate = row.startDate
        event.endDate = row.endDate
        event.notes = row.notes
        event.teams = teams
        if let training = event as? Training {
            training.durationMinutes = row.durationMinutes ?? training.durationMinutes
            training.focusArea = row.focusArea ?? training.focusArea
            if !row.status.isEmpty { training.status = row.status }
        }
        if let tournament = event as? Tournament {
            tournament.maxTeams = row.maxTeams ?? tournament.maxTeams
            if !row.status.isEmpty { tournament.status = row.status }
        }
    }

    /// Anonymous and pending accounts: only the public schedule. Everything
    /// else is removed from the cache — but not before this device's
    /// CloudKit-era data has been handed over (`handOverFromCloudKitIfNeeded`
    /// needs a full-access sync; until then nothing local is deleted).
    func pullSchedule(modelContext: ModelContext) async throws {
        let mayRemove = isHandoverDone
        try await pull("public_schedule", columns: "id,kind,title,sport,location,city,start_date,end_date,status,updated_at",
                       modelContext: modelContext, prune: SportEvent.self, id: \.id, pruneMissing: mayRemove,
                       rowID: { (row: PublicScheduleDBRow) in row.id }, updatedAt: \.updatedAt) { row in
            let event: SportEvent
            if let existing = findEvent(row.id, modelContext: modelContext) {
                event = existing
            } else if row.kind == "tournament" {
                event = Tournament(id: row.id, title: row.title, sport: row.sport, location: row.location,
                                   street: "", zip: "", city: row.city, country: "", startDate: row.startDate,
                                   endDate: row.endDate, maxTeams: 8, status: row.status, notes: "",
                                   createdBy: "", createdAt: row.startDate, teams: [])
                modelContext.insert(event)
            } else {
                event = Training(id: row.id, title: row.title, sport: row.sport, location: row.location,
                                 street: "", zip: "", city: row.city, country: "", startDate: row.startDate,
                                 durationMinutes: 90, focusArea: "", status: row.status, notes: "",
                                 createdBy: "", createdAt: row.startDate, teams: [])
                modelContext.insert(event)
            }
            event.title = row.title
            event.sport = row.sport
            event.location = row.location
            event.city = row.city
            event.startDate = row.startDate
            event.endDate = row.endDate
            if let training = event as? Training, !row.status.isEmpty { training.status = row.status }
            if let tournament = event as? Tournament, !row.status.isEmpty { tournament.status = row.status }
        }
        guard mayRemove else { return }
        removeAll(Attendance.self, modelContext: modelContext)
        removeAll(EventParticipation.self, modelContext: modelContext)
        removeAll(EventImage.self, modelContext: modelContext)
        removeAll(ExpenseReceipt.self, modelContext: modelContext)
        removeAll(TrainingFavorite.self, modelContext: modelContext)
        removeAll(MemberChangeRequest.self, modelContext: modelContext)
        removeAll(TeamMembership.self, modelContext: modelContext)
        removeAll(Team.self, modelContext: modelContext)
        removeAll(Member.self, modelContext: modelContext)
        removeAll(BudgetEntry.self, modelContext: modelContext)
        removeAll(EventMembership.self, modelContext: modelContext)
        // Schedule rows are deleted through the same log as events.
        try await applyDeletions(modelContext: modelContext, tables: ["events"])
    }

    private func removeAll<Model: PersistentModel>(_ type: Model.Type, modelContext: ModelContext) {
        for object in (try? modelContext.fetch(FetchDescriptor<Model>())) ?? [] {
            modelContext.delete(object)
        }
    }

    // MARK: - Attendance

    func pushAttendance(_ attendance: Attendance) {
        save(AttendanceDBRow(attendance), table: "attendances", id: attendance.id)
    }

    func deleteAttendance(id: UUID, isTournamentEvent: Bool) {
        delete(table: "attendances", id: id)
    }

    func pullAttendances(modelContext: ModelContext) async throws {
        try await pull("attendances", modelContext: modelContext, prune: Attendance.self, id: \.id,
                       rowID: { (row: AttendanceDBRow) in row.id }, updatedAt: \.updatedAt) { row in
            let rowID = row.id
            var descriptor = FetchDescriptor<Attendance>(predicate: #Predicate { $0.id == rowID })
            descriptor.fetchLimit = 1
            if let existing = try? modelContext.fetch(descriptor).first {
                existing.attended = row.attended
                existing.recordedAt = row.recordedAt
                existing.praeAmount = row.praeAmount
            } else if let event = findEvent(row.eventID, modelContext: modelContext),
                      let membership = findMembership(row.membershipID, modelContext: modelContext) {
                modelContext.insert(Attendance(id: row.id, event: event, membership: membership,
                                               attended: row.attended, recordedAt: row.recordedAt,
                                               praeAmount: row.praeAmount))
            }
        }
    }

    // MARK: - Participations

    func pushParticipation(_ participation: EventParticipation) {
        save(EventParticipationDBRow(participation), table: "event_participations", id: participation.id)
    }

    func pullParticipations(modelContext: ModelContext) async throws {
        try await pull("event_participations", modelContext: modelContext, prune: EventParticipation.self,
                       id: \.id, rowID: { (row: EventParticipationDBRow) in row.id }, updatedAt: \.updatedAt) { row in
            let rowID = row.id
            var descriptor = FetchDescriptor<EventParticipation>(predicate: #Predicate { $0.id == rowID })
            descriptor.fetchLimit = 1
            if let existing = try? modelContext.fetch(descriptor).first {
                existing.status = row.status
            } else if let user = findUser(row.userID, modelContext: modelContext),
                      let event = findEvent(row.eventID, modelContext: modelContext) {
                modelContext.insert(EventParticipation(id: row.id, user: user, event: event,
                                                       status: row.status, registeredAt: row.registeredAt))
            }
        }
    }

    // MARK: - Direct event members

    func pushEventMembership(_ membership: EventMembership) {
        save(EventMembershipDBRow(membership), table: "event_memberships", id: membership.id)
    }
    func deleteEventMembership(_ id: UUID) { delete(table: "event_memberships", id: id) }

    func pullEventMemberships(modelContext: ModelContext) async throws {
        try await pull("event_memberships", modelContext: modelContext, prune: EventMembership.self, id: \.id,
                       rowID: { (row: EventMembershipDBRow) in row.id }, updatedAt: \.updatedAt) { row in
            let rowID = row.id
            var descriptor = FetchDescriptor<EventMembership>(predicate: #Predicate { $0.id == rowID })
            descriptor.fetchLimit = 1
            guard (try? modelContext.fetch(descriptor).first) == nil,
                  let event = findEvent(row.eventID, modelContext: modelContext) else { return }
            let user = row.userID.flatMap { findUser($0, modelContext: modelContext) }
            let member = row.memberID.flatMap { findMember($0, modelContext: modelContext) }
            guard user != nil || member != nil else { return }
            modelContext.insert(EventMembership(id: row.id, user: user, member: member, event: event,
                                                addedAt: row.addedAt))
        }
    }

    // MARK: - Budget

    func pushBudgetEntry(_ entry: BudgetEntry) {
        save(BudgetEntryDBRow(entry), table: "budget_entries", id: entry.id)
    }
    func deleteBudgetEntry(_ id: UUID) { delete(table: "budget_entries", id: id) }

    func pullBudgetEntries(modelContext: ModelContext) async throws {
        try await pull("budget_entries", modelContext: modelContext, prune: BudgetEntry.self, id: \.id,
                       rowID: { (row: BudgetEntryDBRow) in row.id }, updatedAt: \.updatedAt) { row in
            let category = BudgetCategory.normalize(row.category)
            let event = row.eventID.flatMap { findEvent($0, modelContext: modelContext) }
            let rowID = row.id
            var descriptor = FetchDescriptor<BudgetEntry>(predicate: #Predicate { $0.id == rowID })
            descriptor.fetchLimit = 1
            if let existing = try? modelContext.fetch(descriptor).first {
                existing.category = category
                existing.amount = row.amount
                existing.date = row.date
                existing.note = row.note
                existing.event = event
            } else {
                modelContext.insert(BudgetEntry(id: row.id, category: category, amount: row.amount, date: row.date,
                                                note: row.note, event: event, createdBy: row.createdBy,
                                                createdAt: row.createdAt))
            }
        }
    }

    // MARK: - Training favourites

    func pushTrainingFavorite(_ favorite: TrainingFavorite) {
        save(TrainingFavoriteDBRow(favorite), table: "training_favorites", id: favorite.id)
    }
    func deleteTrainingFavorite(_ id: UUID) { delete(table: "training_favorites", id: id) }

    func pullTrainingFavorites(modelContext: ModelContext) async throws {
        try await pull("training_favorites", modelContext: modelContext, prune: TrainingFavorite.self, id: \.id,
                       rowID: { (row: TrainingFavoriteDBRow) in row.id }, updatedAt: \.updatedAt) { row in
            let teams = findTeams(row.teamIDs, modelContext: modelContext)
            let rowID = row.id
            var descriptor = FetchDescriptor<TrainingFavorite>(predicate: #Predicate { $0.id == rowID })
            descriptor.fetchLimit = 1
            if let existing = try? modelContext.fetch(descriptor).first {
                existing.title = row.title
                existing.sport = row.sport
                existing.startHour = row.startHour
                existing.startMinute = row.startMinute
                existing.endHour = row.endHour
                existing.endMinute = row.endMinute
                existing.weekday = row.weekday
                existing.location = row.location
                existing.street = row.street
                existing.zip = row.zip
                existing.city = row.city
                existing.country = row.country
                existing.teams = teams
                existing.lastUsedAt = row.lastUsedAt
            } else {
                modelContext.insert(TrainingFavorite(id: row.id, title: row.title, sport: row.sport,
                                                     startHour: row.startHour, startMinute: row.startMinute,
                                                     endHour: row.endHour, endMinute: row.endMinute,
                                                     weekday: row.weekday, location: row.location, street: row.street,
                                                     zip: row.zip, city: row.city, country: row.country,
                                                     teams: teams, lastUsedAt: row.lastUsedAt))
            }
        }
    }

    // MARK: - Welcome text

    func pushWelcomeContent(_ content: WelcomeContent) {
        save(WelcomeContentDBRow(content), table: "welcome_content", id: content.id)
    }

    func pullWelcomeContent(modelContext: ModelContext) async throws {
        try await pull("welcome_content", modelContext: modelContext, prune: WelcomeContent.self, id: \.id,
                       rowID: { (row: WelcomeContentDBRow) in row.id }, updatedAt: \.updatedAt) { row in
            if let existing = WelcomeContent.current(in: modelContext) {
                guard !hasPendingPush(existing.id) else { return }
                existing.markdown = row.markdown
                existing.isEnabled = row.isEnabled
                existing.updatedAt = row.updatedAt ?? existing.updatedAt
            } else {
                modelContext.insert(WelcomeContent(id: row.id, markdown: row.markdown, isEnabled: row.isEnabled,
                                                   updatedAt: row.updatedAt ?? .now))
            }
        }
    }

    // MARK: - Change requests

    /// A new proposal carries the proposer's account (required by RLS); a
    /// review update leaves it untouched.
    func pushMemberChangeRequest(_ request: MemberChangeRequest) {
        let isProposal = request.status == MemberChangeRequest.pendingStatus && request.reviewedAt == nil
        let proposer = isProposal ? AuthContext.current?.claims?.userID : nil
        save(MemberChangeRequestDBRow(request, userID: proposer), table: "member_change_requests", id: request.id)
    }

    func pullMemberChangeRequests(modelContext: ModelContext) async throws {
        try await pull("member_change_requests", modelContext: modelContext, prune: MemberChangeRequest.self,
                       id: \.id, rowID: { (row: MemberChangeRequestDBRow) in row.id }, updatedAt: \.updatedAt) { row in
            let rowID = row.id
            var descriptor = FetchDescriptor<MemberChangeRequest>(predicate: #Predicate { $0.id == rowID })
            descriptor.fetchLimit = 1
            let request: MemberChangeRequest
            if let existing = try? modelContext.fetch(descriptor).first {
                request = existing
            } else {
                let member = findMember(row.memberID, modelContext: modelContext)
                request = MemberChangeRequest(
                    id: row.id, memberID: row.memberID, requestedBy: row.requestedBy, requestedAt: row.requestedAt,
                    status: row.status, reviewedBy: row.reviewedBy, reviewedAt: row.reviewedAt,
                    firstName: row.firstName, lastName: row.lastName, title: row.title, gender: row.gender,
                    birthDate: member?.birthDate, street: row.street, zip: row.zip, city: row.city,
                    country: row.country, email: row.email, phone: row.phone, sportId: row.sportID,
                    svnr: member?.svnr ?? "", iban: member?.iban ?? "",
                    lastMedicalExamination: member?.lastMedicalExamination)
                modelContext.insert(request)
            }
            request.status = row.status
            request.reviewedBy = row.reviewedBy
            request.reviewedAt = row.reviewedAt
            request.firstName = row.firstName
            request.lastName = row.lastName
            request.title = row.title
            request.gender = row.gender
            request.street = row.street
            request.zip = row.zip
            request.city = row.city
            request.country = row.country
            request.email = row.email
            request.phone = row.phone
            request.sportId = row.sportID
        }
    }

    // MARK: - Images and receipts (Storage + metadata row)

    /// Uploads the file, then the row. Not outbox-backed (like the CloudKit
    /// asset push before): a failed upload is logged and shown as a sync
    /// failure; the photo stays on this device.
    func pushEventImage(_ image: EventImage) {
        let row = EventImageDBRow(image)
        let data = image.imageData
        Task {
            _ = await performWithRetry("upload of event image \(image.id)") {
                try await self.client.storage.from("event-images")
                    .upload(row.storagePath, data: data, options: FileOptions(contentType: "image/jpeg", upsert: true))
                try await self.client.from("event_images").upsert(row, onConflict: "id", returning: .minimal).execute()
            }
        }
    }

    func deleteEventImage(_ id: UUID) {
        delete(table: "event_images", id: id)
        Task { _ = try? await client.storage.from("event-images").remove(paths: [EventImageDBRow.path(for: id)]) }
    }

    func pullEventImages(modelContext: ModelContext) async throws {
        try await pullFiles("event_images", bucket: "event-images", modelContext: modelContext,
                            prune: EventImage.self, id: \.id, rowID: { (row: EventImageDBRow) in row.id },
                            path: \.storagePath, updatedAt: \.updatedAt,
                            exists: { id in
                                var descriptor = FetchDescriptor<EventImage>(predicate: #Predicate { $0.id == id })
                                descriptor.fetchLimit = 1
                                return (try? modelContext.fetch(descriptor).first) != nil
                            }) { row, data in
            let event = row.eventID.flatMap { findEvent($0, modelContext: modelContext) }
            modelContext.insert(EventImage(id: row.id, imageData: data, uploadedBy: row.uploadedBy,
                                           uploadedAt: row.uploadedAt, event: event))
        }
    }

    func pushExpenseReceipt(_ receipt: ExpenseReceipt) {
        let row = ExpenseReceiptDBRow(receipt)
        let data = receipt.imageData
        Task {
            _ = await performWithRetry("upload of receipt \(receipt.id)") {
                try await self.client.storage.from("receipts")
                    .upload(row.storagePath, data: data, options: FileOptions(contentType: "image/jpeg", upsert: true))
                try await self.client.from("expense_receipts").upsert(row, onConflict: "id", returning: .minimal).execute()
            }
        }
    }

    func deleteExpenseReceipt(_ id: UUID) {
        delete(table: "expense_receipts", id: id)
        Task { _ = try? await client.storage.from("receipts").remove(paths: [ExpenseReceiptDBRow.path(for: id)]) }
    }

    func pullExpenseReceipts(modelContext: ModelContext) async throws {
        try await pullFiles("expense_receipts", bucket: "receipts", modelContext: modelContext,
                            prune: ExpenseReceipt.self, id: \.id, rowID: { (row: ExpenseReceiptDBRow) in row.id },
                            path: \.storagePath, updatedAt: \.updatedAt,
                            exists: { id in
                                var descriptor = FetchDescriptor<ExpenseReceipt>(predicate: #Predicate { $0.id == id })
                                descriptor.fetchLimit = 1
                                return (try? modelContext.fetch(descriptor).first) != nil
                            }) { row, data in
            let tournament = row.tournamentID.flatMap { findEvent($0, modelContext: modelContext) as? Tournament }
            modelContext.insert(ExpenseReceipt(id: row.id, imageData: data, uploadedBy: row.uploadedBy,
                                               uploadedAt: row.uploadedAt, note: row.note, month: row.month,
                                               year: row.year, tournament: tournament))
        }
    }

    /// Like `pull`, but downloads the file for rows not yet cached. A failed
    /// download keeps the cursor where it was, so the next sync retries.
    private func pullFiles<Row: Decodable & Sendable, Model: PersistentModel>(
        _ table: String, bucket: String, modelContext: ModelContext, prune model: Model.Type,
        id modelID: (Model) -> UUID, rowID: (Row) -> UUID, path: (Row) -> String, updatedAt: (Row) -> Date?,
        exists: (UUID) -> Bool, insert: (Row, Data) -> Void
    ) async throws {
        let since = cursor(table)
        let rows: [Row] = try await fetchChanged(table, since: since)
        var allDownloaded = true
        for row in rows where !exists(rowID(row)) {
            do {
                insert(row, try await client.storage.from(bucket).download(path: path(row)))
            } catch {
                allDownloaded = false
                let objectPath = path(row)
                logger.error("download \(bucket, privacy: .public)/\(objectPath, privacy: .public) failed: \(String(describing: error), privacy: .public)")
            }
        }
        if since == nil {
            let keep = Set(rows.map(rowID))
            for object in (try? modelContext.fetch(FetchDescriptor<Model>())) ?? []
            where !keep.contains(modelID(object)) && !hasPendingPush(modelID(object)) {
                modelContext.delete(object)
            }
        }
        if allDownloaded { setCursor(table, rows.compactMap(updatedAt).max()) }
    }

    // MARK: - Deletions

    /// Removes local copies of rows deleted on the server since the last sync.
    func applyDeletions(modelContext: ModelContext, tables: Set<String>? = nil) async throws {
        let since = cursor("deletions")
        var collected: [DeletionDBRow] = []
        var offset = 0
        while true {
            var query = client.from("deletions").select()
            if let since { query = query.gte("deleted_at", value: Self.iso(since)) }
            let page: [DeletionDBRow] = try await query.order("deleted_at", ascending: true)
                .range(from: offset, to: offset + 999).execute().value
            collected += page
            guard page.count == 1000 else { break }
            offset += 1000
        }
        for deletion in collected where tables?.contains(deletion.tableName) ?? true {
            guard !hasPendingPush(deletion.rowID) else { continue }
            deleteLocal(table: deletion.tableName, id: deletion.rowID, modelContext: modelContext)
        }
        setCursor("deletions", collected.map(\.deletedAt).max())
    }

    private func deleteLocal(table: String, id: UUID, modelContext: ModelContext) {
        func delete<Model: PersistentModel>(_ type: Model.Type, _ predicate: Predicate<Model>) {
            for object in (try? modelContext.fetch(FetchDescriptor<Model>(predicate: predicate))) ?? [] {
                modelContext.delete(object)
            }
        }
        switch table {
        case "members": delete(Member.self, #Predicate { $0.id == id })
        case "teams": delete(Team.self, #Predicate { $0.id == id })
        case "team_memberships": delete(TeamMembership.self, #Predicate { $0.id == id })
        case "events": delete(SportEvent.self, #Predicate { $0.id == id })
        case "attendances": delete(Attendance.self, #Predicate { $0.id == id })
        case "event_participations": delete(EventParticipation.self, #Predicate { $0.id == id })
        case "event_memberships": delete(EventMembership.self, #Predicate { $0.id == id })
        case "budget_entries": delete(BudgetEntry.self, #Predicate { $0.id == id })
        case "training_favorites": delete(TrainingFavorite.self, #Predicate { $0.id == id })
        case "member_change_requests": delete(MemberChangeRequest.self, #Predicate { $0.id == id })
        case "event_images": delete(EventImage.self, #Predicate { $0.id == id })
        case "expense_receipts": delete(ExpenseReceipt.self, #Predicate { $0.id == id })
        default: break // member_contacts, welcome_content: nothing separate to remove
        }
    }
}
