import Foundation
import SwiftData

@Model
final class User {
    @Attribute(.unique) var id: UUID = UUID()
    var email: String = ""
    var firstName: String = ""
    var lastName: String = ""
    var role: String = "member" // "member", "coach", "admin"
    var appleUserIdentifier: String = ""
    var createdAt: Date = Date.now
    // Set automatically on account creation by matching against the Member roster.
    var isGrazerVSCMember: Bool = false
    // Super-user flag, distinct from `role`. Only a root account can change another
    // account's `role`; nobody (including root) can change their own via the app —
    // see EditAccountView/UserListView. Set by RootView on first-ever account
    // creation, automatically for the club's designated account (see
    // elevateIfDesignatedRoot below), or externally via the RootCLI tool talking
    // directly to CloudKit.
    var isRoot: Bool = false

    @Relationship(deleteRule: .cascade, inverse: \TeamMembership.user)
    var memberships: [TeamMembership] = []

    @Relationship(deleteRule: .cascade, inverse: \EventParticipation.user)
    var participations: [EventParticipation] = []

    init(id: UUID = UUID(),
         email: String,
         firstName: String,
         lastName: String,
         role: String = "member",
         appleUserIdentifier: String = "",
         createdAt: Date = .now,
         isGrazerVSCMember: Bool = false,
         isRoot: Bool = false) {
        self.id = id
        self.email = email
        self.firstName = firstName
        self.lastName = lastName
        self.role = role
        self.appleUserIdentifier = appleUserIdentifier
        self.createdAt = createdAt
        self.isGrazerVSCMember = isGrazerVSCMember
        self.isRoot = isRoot
    }
}

extension User {
    /// Combines firstName/lastName for display; not stored, so it can't be
    /// used as a @Query sort key path — sort by lastName/firstName instead.
    /// Mirrors Member.fullName's pattern so existing display call sites
    /// (avatar initial, headers, member pickers) didn't need their own
    /// formatting logic.
    var displayName: String {
        [firstName, lastName].filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.joined(separator: " ")
    }

    // Grants root/admin automatically to the club's designated account, matched
    // by firstName + lastName + email together — no Apple Sign-In/
    // appleUserIdentifier gate. Originally gated on a verified Apple email
    // (see RootView's old designatedRootEmail), but that account has no real
    // Apple ID and is always created via RegisterView's manual form, so an
    // Apple-verification requirement could never fire. Requiring all three
    // fields (not email alone) keeps the bar for typing your way to root
    // reasonably high even without Apple's server-side verification. Called
    // from every place these three fields can be set/edited: RootView's
    // account-resolution/login paths, RegisterView's manual creation, and
    // EditAccountView whenever firstName/lastName/email change — same call
    // sites as elevateIfTestAdmin below.
    static let designatedRootFirstName = "Blindensport"
    static let designatedRootLastName = "Graz"
    static let designatedRootEmail = "blindensport.gvsc@gmail.com"

    @discardableResult
    func elevateIfDesignatedRoot() -> Bool {
        guard firstName.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(User.designatedRootFirstName) == .orderedSame,
              lastName.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(User.designatedRootLastName) == .orderedSame,
              email.trimmingCharacters(in: .whitespaces).lowercased() == User.designatedRootEmail,
              !isRoot else { return false }
        isRoot = true
        role = "admin"
        return true
    }

    // TEST-ONLY: temporarily promotes this one account to `role = "admin"`
    // (not root — see elevateIfDesignatedRoot above for the real, production
    // escalation mechanism) so admin-only screens can be tested.
    // Deliberately matched by email alone with NO Apple-verification/
    // appleUserIdentifier gate — unlike the root grant, the user explicitly
    // scoped this as "only needed for test issues", and a stricter gate was
    // actively preventing it from firing for a manually-registered (or
    // Apple hide-my-email-affected) test account. Called from every place a
    // User's email could become this value: RootView's account-resolution/
    // login paths, RegisterView's manual creation, and EditAccountView
    // whenever the email field changes. Requested 2026-07-19 — remove this
    // whole block, and its call sites, once testing is done.
    static let testAdminEmail = "franz.kager@gmx.net"

    @discardableResult
    func elevateIfTestAdmin() -> Bool {
        let normalized = email.trimmingCharacters(in: .whitespaces).lowercased()
        guard normalized == User.testAdminEmail, role != "admin" else { return false }
        role = "admin"
        return true
    }
}

/// Roster administered by admins under "Benutzerverwaltung" (user management).
/// Formerly named `ClubMember` and implicitly always a Grazer VSC member by
/// virtue of being on the roster at all; `memberOfGVSC` now makes that an
/// explicit, editable flag instead, since this roster also carries
/// helpers/coaches (`defaultFunction`) who aren't necessarily formal club
/// members. Used to automatically flag matching app accounts as club members
/// on creation (see `User.isGrazerVSCMember`) — that account-level flag is
/// distinct from this per-roster-entry `memberOfGVSC` flag.
@Model
final class Member {
    @Attribute(.unique) var id: UUID = UUID()
    var firstName: String = ""
    var lastName: String = ""
    var street: String = ""
    var zip: String = ""
    var city: String = ""
    var email: String = ""
    var phone: String = ""
    var memberNumber: String = ""
    var joinedAt: Date = Date.now
    var notes: String = ""
    // Fields below mirror the attributes found in the club's source-of-truth
    // roster JSON files (data/Person-Sport.json, data/Person-Others.json) so
    // that data can be imported without loss. gender/title/sportId/svnr/iban/
    // defaultFunction are free-form strings (source data isn't consistently
    // formatted enough to validate/typecheck further); birthDate and
    // lastMedicalExamination are optional since many roster entries omit them.
    var gender: String = ""
    var title: String = ""
    var birthDate: Date?
    // Sport Austria federation ID (e.g. "St-0046"), distinct from the club's
    // own internal memberNumber.
    var sportId: String = ""
    var svnr: String = ""
    var iban: String = ""
    var lastMedicalExamination: Date?
    // Default TeamMembership.role ("COACH", etc.) for this person, e.g. to
    // pre-fill role when assigning them to a team. Not otherwise enforced.
    var defaultFunction: String = ""
    // Whether this roster entry is an actual Grazer VSC club member, as
    // opposed to e.g. an external helper/coach tracked here without formal
    // membership. Defaults true since every entry historically was one.
    var memberOfGVSC: Bool = true

    @Relationship(deleteRule: .cascade, inverse: \TeamMembership.member)
    var teamMemberships: [TeamMembership] = []

    init(id: UUID = UUID(),
         firstName: String,
         lastName: String,
         street: String = "",
         zip: String = "",
         city: String = "",
         email: String = "",
         phone: String = "",
         memberNumber: String = "",
         joinedAt: Date = .now,
         notes: String = "",
         gender: String = "",
         title: String = "",
         birthDate: Date? = nil,
         sportId: String = "",
         svnr: String = "",
         iban: String = "",
         lastMedicalExamination: Date? = nil,
         defaultFunction: String = "",
         memberOfGVSC: Bool = true) {
        self.id = id
        self.firstName = firstName
        self.lastName = lastName
        self.street = street
        self.zip = zip
        self.city = city
        self.email = email
        self.phone = phone
        self.memberNumber = memberNumber
        self.joinedAt = joinedAt
        self.notes = notes
        self.gender = gender
        self.title = title
        self.birthDate = birthDate
        self.sportId = sportId
        self.svnr = svnr
        self.iban = iban
        self.lastMedicalExamination = lastMedicalExamination
        self.defaultFunction = defaultFunction
        self.memberOfGVSC = memberOfGVSC
    }
}

extension Member {
    /// Combines firstName/lastName for display and matching; not stored, so it
    /// can't be used as a @Query sort key path — sort by lastName/firstName instead.
    var fullName: String {
        [firstName, lastName].filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.joined(separator: " ")
    }

    /// Combines street/zip/city into one display line, e.g. "Hauptstraße 12, 8010 Graz".
    /// Not stored, mirrors fullName's pattern — can't be used as a @Query sort key.
    var fullAddress: String {
        let zipCity = [zip, city].filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.joined(separator: " ")
        return [street, zipCity].filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.joined(separator: ", ")
    }
}

extension Member {
    /// Checks a newly created (or edited) account's email/first+last name against
    /// the local Member roster and updates its `isGrazerVSCMember` flag
    /// accordingly.
    static func checkMembership(for user: User, modelContext: ModelContext) {
        let roster = (try? modelContext.fetch(FetchDescriptor<Member>())) ?? []
        user.isGrazerVSCMember = matches(email: user.email, firstName: user.firstName,
                                          lastName: user.lastName, in: roster)
    }

    /// Matches a new account's email or first+last name against the roster, case-
    /// and whitespace-insensitively. Email match takes priority since names can
    /// collide; first/last name are compared as separate fields (not a joined
    /// full-name string) since that's how both User and Member store them.
    static func matches(email: String, firstName: String, lastName: String, in roster: [Member]) -> Bool {
        firstMatch(email: email, firstName: firstName, lastName: lastName, in: roster) != nil
    }

    /// Finds the specific roster entry a `User` matches, using the same rules as
    /// `matches` — used by AccountView to let a Grazer VSC member (isGrazerVSCMember
    /// == true) edit their own roster data (address, phone, ...) directly, without
    /// needing admin access to MembersListView.
    static func first(matching user: User, in roster: [Member]) -> Member? {
        firstMatch(email: user.email, firstName: user.firstName, lastName: user.lastName, in: roster)
    }

    private static func firstMatch(email: String, firstName: String, lastName: String, in roster: [Member]) -> Member? {
        let normalizedEmail = email.trimmingCharacters(in: .whitespaces).lowercased()
        let normalizedFirst = firstName.trimmingCharacters(in: .whitespaces).lowercased()
        let normalizedLast = lastName.trimmingCharacters(in: .whitespaces).lowercased()
        guard !normalizedEmail.isEmpty || (!normalizedFirst.isEmpty && !normalizedLast.isEmpty) else { return nil }

        return roster.first { member in
            let memberEmail = member.email.trimmingCharacters(in: .whitespaces).lowercased()
            if !normalizedEmail.isEmpty, !memberEmail.isEmpty, memberEmail == normalizedEmail {
                return true
            }
            let memberFirst = member.firstName.trimmingCharacters(in: .whitespaces).lowercased()
            let memberLast = member.lastName.trimmingCharacters(in: .whitespaces).lowercased()
            return !normalizedFirst.isEmpty && !normalizedLast.isEmpty &&
                   memberFirst == normalizedFirst && memberLast == normalizedLast
        }
    }
}

@Model
final class Team {
    @Attribute(.unique) var id: UUID = UUID()
    var name: String = ""
    var sport: String = ""
    var descriptionText: String = ""
    var createdAt: Date = Date.now

    @Relationship(deleteRule: .cascade, inverse: \TeamMembership.team)
    var memberships: [TeamMembership] = []

    // Never read directly anywhere in the app (SportEvent/Training/Tournament
    // membership is always navigated the other way, filtering `.teams`
    // client-side) — this exists so deleteRule: .nullify protects any
    // assigned event/training/tournament from a dangling Team reference when
    // a team is deleted (see TeamsViews.swift's delete). One relationship
    // covers all three now that Training/Tournament are SportEvent subclasses.
    @Relationship(deleteRule: .nullify, inverse: \SportEvent.teams)
    var sportEvents: [SportEvent] = []

    init(id: UUID = UUID(),
         name: String,
         sport: String,
         descriptionText: String = "",
         createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.sport = sport
        self.descriptionText = descriptionText
        self.createdAt = createdAt
    }
}

extension Team {
    /// The club's standing teams, expected to always exist — recreated
    /// automatically by `CloudKitSync.ensureDefaultTeams` on every launch if
    /// missing (e.g. very first launch ever, or a local store rebuilt from a
    /// ModelContainer migration reset — see the 2026-08-01 rename entry in
    /// cerebrum.md). Kept as a plain data constant next to the model, same
    /// convention as `User.designatedRootEmail`.
    static let defaultTeams: [(name: String, sport: String)] = [
        ("Grazer VSC Damen", "Torball"),
        ("Grazer VSC Herren", "Torball"),
        ("Blindenfußball", "Blindenfußball"),
        // Not tied to one sport — groups helpers/coaches (TeamMembership.role
        // "assistant"/"coach") who support across multiple teams, so this one
        // deliberately has no sport value.
        ("Helfer", ""),
    ]
}

/// Exactly one of `user`/`member` is set, never both/neither. `user` covers
/// people with a registered app account; `member` covers Grazer VSC roster
/// entries who haven't signed into the app yet — teams routinely include both,
/// since real club rosters aren't 1:1 with app installs.
@Model
final class TeamMembership {
    @Attribute(.unique) var id: UUID = UUID()
    var user: User?
    var member: Member?
    var team: Team
    var role: String = "player" // "player", "coach", "assistant"
    var joinedAt: Date = Date.now

    // Attendance.membership is a non-optional to-one relationship — without
    // this explicit cascade+inverse, deleting a TeamMembership (TeamsViews'
    // roster swipe-to-delete, or via Team's own cascade delete) leaves
    // SwiftData trying to nullify a non-optional property on any dependent
    // Attendance, which corrupts that Attendance's backing row instead of
    // failing cleanly — any later access to `attendance.membership.id`
    // (TrainingDetailView/TournamentDetailView.attendance(for:)) then
    // crashes with a fatal SwiftData assertion. See bug-163.
    @Relationship(deleteRule: .cascade, inverse: \Attendance.membership)
    var attendances: [Attendance] = []

    init(id: UUID = UUID(),
         user: User? = nil,
         member: Member? = nil,
         team: Team,
         role: String = "player",
         joinedAt: Date = .now) {
        self.id = id
        self.user = user
        self.member = member
        self.team = team
        self.role = role
        self.joinedAt = joinedAt
    }
}

extension TeamMembership {
    var displayName: String {
        user?.displayName ?? member?.fullName ?? "?"
    }

    // Same user/member fallback chain as displayName — TeamMembership has no
    // stored lastName/firstName of its own, only via whichever of user/member
    // is set.
    var lastName: String { user?.lastName ?? member?.lastName ?? "" }
    var firstName: String { user?.firstName ?? member?.firstName ?? "" }

    /// Secondary line under the name in member lists: indicates whether this
    /// roster entry is linked to a registered app account, or is roster-only
    /// (no account yet). Used to be "@username", but User no longer has a
    /// username field — email can't be shown here instead since it's
    /// deliberately never synced to CloudKit (see CloudKitSync's doc
    /// comment), so a `user` pulled from another device would show blank.
    var subtitle: String {
        if user != nil { return "Konto vorhanden" }
        return "Grazer VSC – kein Konto"
    }
}

extension Sequence where Element == TeamMembership {
    /// Standard sort order for every member list in the app: lastName, then
    /// firstName as a tiebreaker — matches how User/Member rosters are
    /// already sorted (RootView.LoginView, MembersListView).
    func sortedByLastName() -> [TeamMembership] {
        sorted { ($0.lastName, $0.firstName) < ($1.lastName, $1.firstName) }
    }
}

/// Base type for anything that's fundamentally "a sport happening at a place
/// and time": a plain SportEvent, or (via the Training/Tournament subclasses
/// below) a training session or a tournament. `kind` is a stored
/// discriminator ("event"/"training"/"tournament") — SwiftData's polymorphic
/// fetch means a plain `@Query`/`FetchDescriptor<SportEvent>` returns
/// Training/Tournament instances too, so any query that wants ONLY plain
/// events (EventsListView, DashboardView) must filter on `kind == "event"`.
@Model
@available(iOS 26, *)
class SportEvent {
    @Attribute(.unique) var id: UUID = UUID()
    var kind: String = "event" // "event", "training", "tournament"
    var title: String = ""
    var sport: String = ""
    var location: String = ""
    var startDate: Date = Date.now
    var endDate: Date = Date.now
    var notes: String = ""
    var createdBy: String = ""
    var createdAt: Date = Date.now
    // Empty = visible to everyone; non-empty = scoped to members of any listed team.
    var teams: [Team] = []

    @Relationship(deleteRule: .cascade, inverse: \EventParticipation.event)
    var participations: [EventParticipation] = []

    @Relationship(deleteRule: .cascade, inverse: \EventImage.event)
    var images: [EventImage] = []

    @Relationship(deleteRule: .cascade, inverse: \Attendance.event)
    var attendances: [Attendance] = []

    init(id: UUID = UUID(),
         title: String,
         sport: String,
         location: String,
         startDate: Date,
         endDate: Date,
         notes: String = "",
         createdBy: String = "",
         createdAt: Date = .now,
         teams: [Team] = []) {
        self.id = id
        self.title = title
        self.sport = sport
        self.location = location
        self.startDate = startDate
        self.endDate = endDate
        self.notes = notes
        self.createdBy = createdBy
        self.createdAt = createdAt
        self.teams = teams
    }
}

@Model
@available(iOS 26, *)
final class Tournament: SportEvent {
    var maxTeams: Int = 8
    var status: String = "planned" // "planned", "ongoing", "finished"

    init(id: UUID = UUID(),
         title: String,
         sport: String,
         location: String,
         startDate: Date,
         endDate: Date,
         maxTeams: Int = 8,
         status: String = "planned",
         notes: String = "",
         createdBy: String = "",
         createdAt: Date = .now,
         teams: [Team] = []) {
        self.maxTeams = maxTeams
        self.status = status
        super.init(id: id, title: title, sport: sport, location: location, startDate: startDate,
                   endDate: endDate, notes: notes, createdBy: createdBy, createdAt: createdAt, teams: teams)
        self.kind = "tournament"
    }
}

@Model
@available(iOS 26, *)
final class Training: SportEvent {
    var durationMinutes: Int = 90
    var focusArea: String = ""

    init(id: UUID = UUID(),
         title: String,
         sport: String,
         location: String,
         startDate: Date,
         durationMinutes: Int = 90,
         focusArea: String = "",
         notes: String = "",
         createdBy: String = "",
         createdAt: Date = .now,
         teams: [Team] = []) {
        self.durationMinutes = durationMinutes
        self.focusArea = focusArea
        let endDate = startDate.addingTimeInterval(TimeInterval(durationMinutes) * 60)
        super.init(id: id, title: title, sport: sport, location: location, startDate: startDate,
                   endDate: endDate, notes: notes, createdBy: createdBy, createdAt: createdAt, teams: teams)
        self.kind = "training"
    }

    /// Keeps the inherited, stored `endDate` in sync with startDate +
    /// durationMinutes. SwiftData model properties don't support
    /// didSet/property-observer sync, so this has to be called explicitly
    /// wherever startDate or durationMinutes changes — see
    /// TrainingDetailView's .onChange handlers.
    func recomputeEndDate() {
        endDate = startDate.addingTimeInterval(TimeInterval(durationMinutes) * 60)
    }
}

/// Attendance record for one team-roster entry (TeamMembership) at one
/// SportEvent — in practice always a Training or Tournament, since only
/// their detail views have an "Anwesenheit" section. Created lazily the
/// first time a checkbox is toggled, not upfront for every assigned member.
@Model
final class Attendance {
    @Attribute(.unique) var id: UUID = UUID()
    var event: SportEvent
    var membership: TeamMembership
    var attended: Bool = false
    var recordedAt: Date = Date.now
    // Pauschale Reiseaufwandsentschädigung (PRAE) amount for this one
    // deployment day, EUR. Nil by default — an admin opts a specific
    // attendance into PRAE by entering an amount (see PraeCalculation.swift),
    // it's never inferred automatically. Only meaningful for coach/assistant
    // memberships (see TrainingsViews/TournamentsViews' Anwesenheit section,
    // which only shows the amount field for those roles) — "helpers and
    // coaches" per the feature request, matching this app's existing
    // TeamMembership.role vocabulary rather than Sport Austria's broader
    // (Sportler:in/Trainer:in/Übungsleiter:in/...) role list.
    var praeAmount: Double?

    init(id: UUID = UUID(),
         event: SportEvent,
         membership: TeamMembership,
         attended: Bool = false,
         recordedAt: Date = .now,
         praeAmount: Double? = nil) {
        self.id = id
        self.event = event
        self.membership = membership
        self.attended = attended
        self.recordedAt = recordedAt
        self.praeAmount = praeAmount
    }
}

/// A photo attached to a SportEvent (or, via inheritance, a Training or
/// Tournament). Randomly featured on that item's detail screen and browsable
/// as a full gallery — see EventImagesSection.
@Model
final class EventImage {
    @Attribute(.unique) var id: UUID = UUID()
    @Attribute(.externalStorage) var imageData: Data = Data()
    var uploadedBy: String = ""
    var uploadedAt: Date = Date.now
    var event: SportEvent?

    init(id: UUID = UUID(),
         imageData: Data,
         uploadedBy: String = "",
         uploadedAt: Date = .now,
         event: SportEvent? = nil) {
        self.id = id
        self.imageData = imageData
        self.uploadedBy = uploadedBy
        self.uploadedAt = uploadedAt
        self.event = event
    }
}

@Model
final class EventParticipation {
    @Attribute(.unique) var id: UUID = UUID()
    var user: User
    var event: SportEvent
    var status: String = "invited" // "invited", "confirmed", "declined"
    var registeredAt: Date = Date.now

    init(id: UUID = UUID(),
         user: User,
         event: SportEvent,
         status: String = "invited",
         registeredAt: Date = .now) {
        self.id = id
        self.user = user
        self.event = event
        self.status = status
        self.registeredAt = registeredAt
    }
}
