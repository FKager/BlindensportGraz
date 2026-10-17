import Foundation

// One row type per Supabase table (migration 20261013000001_club_data).
// Snake-case keys, ids = the former CloudKit record names. `updatedAt` is
// read-only server state (sync cursor); it stays nil when pushing, so the
// synthesized encoder leaves it out and the database trigger sets it.

nonisolated struct TeamDBRow: Codable, Sendable, Equatable {
    var id: UUID
    var name: String
    var sport: String
    var descriptionText: String
    var createdAt: Date
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, sport
        case descriptionText = "description_text"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

nonisolated struct TeamMembershipDBRow: Codable, Sendable, Equatable {
    var id: UUID
    var teamID: UUID
    var memberID: UUID?
    var userID: UUID?
    var role: String
    var joinedAt: Date
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, role
        case teamID = "team_id"
        case memberID = "member_id"
        case userID = "user_id"
        case joinedAt = "joined_at"
        case updatedAt = "updated_at"
    }

    // Optional references are sent as explicit nulls, so clearing a link
    // reaches the server (synthesized Encodable would omit nil).
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(teamID, forKey: .teamID)
        try c.encode(memberID, forKey: .memberID)
        try c.encode(userID, forKey: .userID)
        try c.encode(role, forKey: .role)
        try c.encode(joinedAt, forKey: .joinedAt)
    }
}

/// Roster names — readable by every approved account.
nonisolated struct MemberDBRow: Codable, Sendable, Equatable {
    var id: UUID
    var firstName: String
    var lastName: String
    var memberNumber: String
    var sportID: String
    var defaultFunction: String
    var memberOfGVSC: Bool
    var joinedAt: Date
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case firstName = "first_name"
        case lastName = "last_name"
        case memberNumber = "member_number"
        case sportID = "sport_id"
        case defaultFunction = "default_function"
        case memberOfGVSC = "member_of_gvsc"
        case joinedAt = "joined_at"
        case updatedAt = "updated_at"
    }
}

/// Roster contact details — members.manage, or the member's own entry.
nonisolated struct MemberContactDBRow: Codable, Sendable, Equatable {
    var id: UUID
    var street: String
    var zip: String
    var city: String
    var country: String
    var email: String
    var phone: String
    var notes: String
    var gender: String
    var title: String
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, street, zip, city, country, email, phone, notes, gender, title
        case updatedAt = "updated_at"
    }
}

/// SportEvent / Training / Tournament in one table, told apart by `kind`.
nonisolated struct EventDBRow: Codable, Sendable, Equatable {
    var id: UUID
    var kind: String
    var title: String
    var sport: String
    var location: String
    var street: String
    var zip: String
    var city: String
    var country: String
    var startDate: Date
    var endDate: Date
    var notes: String
    var status: String
    var durationMinutes: Int?
    var focusArea: String?
    var maxTeams: Int?
    var teamIDs: [UUID]
    var createdBy: String
    var createdAt: Date
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, kind, title, sport, location, street, zip, city, country, notes, status
        case startDate = "start_date"
        case endDate = "end_date"
        case durationMinutes = "duration_minutes"
        case focusArea = "focus_area"
        case maxTeams = "max_teams"
        case teamIDs = "team_ids"
        case createdBy = "created_by"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(kind, forKey: .kind)
        try c.encode(title, forKey: .title)
        try c.encode(sport, forKey: .sport)
        try c.encode(location, forKey: .location)
        try c.encode(street, forKey: .street)
        try c.encode(zip, forKey: .zip)
        try c.encode(city, forKey: .city)
        try c.encode(country, forKey: .country)
        try c.encode(startDate, forKey: .startDate)
        try c.encode(endDate, forKey: .endDate)
        try c.encode(notes, forKey: .notes)
        try c.encode(status, forKey: .status)
        try c.encode(durationMinutes, forKey: .durationMinutes)
        try c.encode(focusArea, forKey: .focusArea)
        try c.encode(maxTeams, forKey: .maxTeams)
        try c.encode(teamIDs, forKey: .teamIDs)
        try c.encode(createdBy, forKey: .createdBy)
        try c.encode(createdAt, forKey: .createdAt)
    }
}

/// `public_schedule` view: what anonymous and pending accounts may see.
nonisolated struct PublicScheduleDBRow: Codable, Sendable, Equatable {
    var id: UUID
    var kind: String
    var title: String
    var sport: String
    var location: String
    var city: String
    var startDate: Date
    var endDate: Date
    var status: String
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, kind, title, sport, location, city, status
        case startDate = "start_date"
        case endDate = "end_date"
        case updatedAt = "updated_at"
    }
}

nonisolated struct AttendanceDBRow: Codable, Sendable, Equatable {
    var id: UUID
    var eventID: UUID
    var membershipID: UUID
    var attended: Bool
    var recordedAt: Date
    var praeAmount: Double?
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, attended
        case eventID = "event_id"
        case membershipID = "membership_id"
        case recordedAt = "recorded_at"
        case praeAmount = "prae_amount"
        case updatedAt = "updated_at"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(eventID, forKey: .eventID)
        try c.encode(membershipID, forKey: .membershipID)
        try c.encode(attended, forKey: .attended)
        try c.encode(recordedAt, forKey: .recordedAt)
        try c.encode(praeAmount, forKey: .praeAmount)
    }
}

nonisolated struct EventParticipationDBRow: Codable, Sendable, Equatable {
    var id: UUID
    var eventID: UUID
    var userID: UUID
    var status: String
    var registeredAt: Date
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, status
        case eventID = "event_id"
        case userID = "user_id"
        case registeredAt = "registered_at"
        case updatedAt = "updated_at"
    }
}

nonisolated struct EventMembershipDBRow: Codable, Sendable, Equatable {
    var id: UUID
    var eventID: UUID
    var memberID: UUID?
    var userID: UUID?
    var addedAt: Date
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case eventID = "event_id"
        case memberID = "member_id"
        case userID = "user_id"
        case addedAt = "added_at"
        case updatedAt = "updated_at"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(eventID, forKey: .eventID)
        try c.encode(memberID, forKey: .memberID)
        try c.encode(userID, forKey: .userID)
        try c.encode(addedAt, forKey: .addedAt)
    }
}

nonisolated struct BudgetEntryDBRow: Codable, Sendable, Equatable {
    var id: UUID
    var category: String
    var amount: Double
    var date: Date
    var note: String
    var eventID: UUID?
    var createdBy: String
    var createdAt: Date
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, category, amount, date, note
        case eventID = "event_id"
        case createdBy = "created_by"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(category, forKey: .category)
        try c.encode(amount, forKey: .amount)
        try c.encode(date, forKey: .date)
        try c.encode(note, forKey: .note)
        try c.encode(eventID, forKey: .eventID)
        try c.encode(createdBy, forKey: .createdBy)
        try c.encode(createdAt, forKey: .createdAt)
    }
}

nonisolated struct TrainingFavoriteDBRow: Codable, Sendable, Equatable {
    var id: UUID
    var title: String
    var sport: String
    var weekday: Int
    var startHour: Int
    var startMinute: Int
    var endHour: Int
    var endMinute: Int
    var location: String
    var street: String
    var zip: String
    var city: String
    var country: String
    var teamIDs: [UUID]
    var lastUsedAt: Date
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, title, sport, weekday, location, street, zip, city, country
        case startHour = "start_hour"
        case startMinute = "start_minute"
        case endHour = "end_hour"
        case endMinute = "end_minute"
        case teamIDs = "team_ids"
        case lastUsedAt = "last_used_at"
        case updatedAt = "updated_at"
    }
}

nonisolated struct WelcomeContentDBRow: Codable, Sendable, Equatable {
    var id: UUID
    var markdown: String
    var isEnabled: Bool
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, markdown
        case isEnabled = "is_enabled"
        case updatedAt = "updated_at"
    }
}

/// Contact-data proposals; protected fields go through
/// `member_private_requests` (SupabaseMemberPrivateService) instead.
nonisolated struct MemberChangeRequestDBRow: Codable, Sendable, Equatable {
    var id: UUID
    var memberID: UUID
    var userID: UUID?
    var requestedBy: String
    var requestedAt: Date
    var status: String
    var reviewedBy: String
    var reviewedAt: Date?
    var firstName: String
    var lastName: String
    var title: String
    var gender: String
    var street: String
    var zip: String
    var city: String
    var country: String
    var email: String
    var phone: String
    var sportID: String
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, status, title, gender, street, zip, city, country, email, phone
        case memberID = "member_id"
        case userID = "user_id"
        case requestedBy = "requested_by"
        case requestedAt = "requested_at"
        case reviewedBy = "reviewed_by"
        case reviewedAt = "reviewed_at"
        case firstName = "first_name"
        case lastName = "last_name"
        case sportID = "sport_id"
        case updatedAt = "updated_at"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(memberID, forKey: .memberID)
        // The reviewer's update must not overwrite the proposer.
        try c.encodeIfPresent(userID, forKey: .userID)
        try c.encode(requestedBy, forKey: .requestedBy)
        try c.encode(requestedAt, forKey: .requestedAt)
        try c.encode(status, forKey: .status)
        try c.encode(reviewedBy, forKey: .reviewedBy)
        try c.encode(reviewedAt, forKey: .reviewedAt)
        try c.encode(firstName, forKey: .firstName)
        try c.encode(lastName, forKey: .lastName)
        try c.encode(title, forKey: .title)
        try c.encode(gender, forKey: .gender)
        try c.encode(street, forKey: .street)
        try c.encode(zip, forKey: .zip)
        try c.encode(city, forKey: .city)
        try c.encode(country, forKey: .country)
        try c.encode(email, forKey: .email)
        try c.encode(phone, forKey: .phone)
        try c.encode(sportID, forKey: .sportID)
    }
}

nonisolated struct EventImageDBRow: Codable, Sendable, Equatable {
    var id: UUID
    var eventID: UUID?
    var storagePath: String
    var uploadedBy: String
    var uploadedAt: Date
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case eventID = "event_id"
        case storagePath = "storage_path"
        case uploadedBy = "uploaded_by"
        case uploadedAt = "uploaded_at"
        case updatedAt = "updated_at"
    }
}

nonisolated struct ExpenseReceiptDBRow: Codable, Sendable, Equatable {
    var id: UUID
    var tournamentID: UUID?
    var storagePath: String
    var note: String
    var month: Int?
    var year: Int?
    var uploadedBy: String
    var uploadedAt: Date
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, note, month, year
        case tournamentID = "tournament_id"
        case storagePath = "storage_path"
        case uploadedBy = "uploaded_by"
        case uploadedAt = "uploaded_at"
        case updatedAt = "updated_at"
    }
}

/// `public.deletions` — ids of rows deleted on the server.
nonisolated struct DeletionDBRow: Codable, Sendable, Equatable {
    var tableName: String
    var rowID: UUID
    var deletedAt: Date

    enum CodingKeys: String, CodingKey {
        case tableName = "table_name"
        case rowID = "row_id"
        case deletedAt = "deleted_at"
    }
}

// MARK: - From local models (push side)

extension TeamDBRow {
    init(_ team: Team) {
        self.init(id: team.id, name: team.name, sport: team.sport, descriptionText: team.descriptionText,
                  createdAt: team.createdAt)
    }
}

extension TeamMembershipDBRow {
    init(_ membership: TeamMembership) {
        self.init(id: membership.id, teamID: membership.team.id, memberID: membership.member?.id,
                  userID: membership.user?.id, role: membership.role.rawValue, joinedAt: membership.joinedAt)
    }
}

extension MemberDBRow {
    init(_ member: Member) {
        self.init(id: member.id, firstName: member.firstName, lastName: member.lastName,
                  memberNumber: member.memberNumber, sportID: member.sportId,
                  defaultFunction: member.defaultFunction, memberOfGVSC: member.memberOfGVSC,
                  joinedAt: member.joinedAt)
    }
}

extension MemberContactDBRow {
    init(_ member: Member) {
        self.init(id: member.id, street: member.street, zip: member.zip, city: member.city,
                  country: member.country, email: member.email, phone: member.phone, notes: member.notes,
                  gender: member.gender, title: member.title)
    }
}

extension EventDBRow {
    init(_ event: SportEvent) {
        let training = event as? Training
        let tournament = event as? Tournament
        self.init(id: event.id, kind: event.kind, title: event.title, sport: event.sport,
                  location: event.location, street: event.street, zip: event.zip, city: event.city,
                  country: event.country, startDate: event.startDate, endDate: event.endDate,
                  notes: event.notes,
                  status: training?.status ?? tournament?.status ?? "",
                  durationMinutes: training?.durationMinutes, focusArea: training?.focusArea,
                  maxTeams: tournament?.maxTeams,
                  teamIDs: event.teams.map(\.id), createdBy: event.createdBy, createdAt: event.createdAt)
    }
}

extension AttendanceDBRow {
    init(_ attendance: Attendance) {
        self.init(id: attendance.id, eventID: attendance.event.id, membershipID: attendance.membership.id,
                  attended: attendance.attended, recordedAt: attendance.recordedAt,
                  praeAmount: attendance.praeAmount)
    }
}

extension EventParticipationDBRow {
    init(_ participation: EventParticipation) {
        self.init(id: participation.id, eventID: participation.event.id, userID: participation.user.id,
                  status: participation.status, registeredAt: participation.registeredAt)
    }
}

extension EventMembershipDBRow {
    init(_ membership: EventMembership) {
        self.init(id: membership.id, eventID: membership.event.id, memberID: membership.member?.id,
                  userID: membership.user?.id, addedAt: membership.addedAt)
    }
}

extension BudgetEntryDBRow {
    init(_ entry: BudgetEntry) {
        self.init(id: entry.id, category: entry.category.rawValue, amount: entry.amount, date: entry.date,
                  note: entry.note, eventID: entry.event?.id, createdBy: entry.createdBy, createdAt: entry.createdAt)
    }
}

extension TrainingFavoriteDBRow {
    init(_ favorite: TrainingFavorite) {
        self.init(id: favorite.id, title: favorite.title, sport: favorite.sport, weekday: favorite.weekday,
                  startHour: favorite.startHour, startMinute: favorite.startMinute,
                  endHour: favorite.endHour, endMinute: favorite.endMinute, location: favorite.location,
                  street: favorite.street, zip: favorite.zip, city: favorite.city, country: favorite.country,
                  teamIDs: favorite.teams.map(\.id), lastUsedAt: favorite.lastUsedAt)
    }
}

extension WelcomeContentDBRow {
    init(_ content: WelcomeContent) {
        self.init(id: content.id, markdown: content.markdown, isEnabled: content.isEnabled)
    }
}

extension MemberChangeRequestDBRow {
    /// `userID`: the proposer (set on creation only, nil for a review).
    init(_ request: MemberChangeRequest, userID: UUID?) {
        self.init(id: request.id, memberID: request.memberID, userID: userID,
                  requestedBy: request.requestedBy, requestedAt: request.requestedAt, status: request.status,
                  reviewedBy: request.reviewedBy, reviewedAt: request.reviewedAt,
                  firstName: request.firstName, lastName: request.lastName, title: request.title,
                  gender: request.gender, street: request.street, zip: request.zip, city: request.city,
                  country: request.country, email: request.email, phone: request.phone,
                  sportID: request.sportId)
    }
}

extension EventImageDBRow {
    init(_ image: EventImage) {
        self.init(id: image.id, eventID: image.event?.id, storagePath: Self.path(for: image.id),
                  uploadedBy: image.uploadedBy, uploadedAt: image.uploadedAt)
    }

    static func path(for id: UUID) -> String { "\(id.uuidString.lowercased()).jpg" }
}

extension ExpenseReceiptDBRow {
    init(_ receipt: ExpenseReceipt) {
        self.init(id: receipt.id, tournamentID: receipt.tournament?.id, storagePath: Self.path(for: receipt.id),
                  note: receipt.note, month: receipt.month, year: receipt.year,
                  uploadedBy: receipt.uploadedBy, uploadedAt: receipt.uploadedAt)
    }

    static func path(for id: UUID) -> String { "\(id.uuidString.lowercased()).jpg" }
}
