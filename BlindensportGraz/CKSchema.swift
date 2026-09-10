import Foundation
import ClubSchema

/// Centralized CKRecord type/field name constants for every record type this
/// app publishes to CloudKit's public database (audit.md Architecture
/// Finding 7 / SwiftData & CloudKit Finding 7). Before this, every
/// record-type/field-name was a bare string literal scattered through
/// `CloudKitSync.swift` — a typo'd literal failed silently at the CloudKit
/// layer (a field just never gets read/written) instead of at compile time.
/// `CloudKitSync.swift` uses these exclusively now; this file changes no
/// behavior, it's a pure extract (see cerebrum.md 2026-08-22).
enum CKSchema {
    enum Team {
        static let recordType = "Team"
        static let name = "name"
        static let sport = "sport"
        static let descriptionText = "descriptionText"
        static let createdAt = "createdAt"
    }

    enum TeamMembership {
        static let recordType = "TeamMembership"
        static let userID = "userID"
        /// Field key stays "clubMemberID" (not renamed to match the app-side
        /// `ClubMember` -> `Member` rename) for wire compatibility with
        /// already-synced production data — see `CloudKitSync.swift`'s top
        /// doc comment and cerebrum.md's 2026-08-01 entry.
        static let clubMemberID = "clubMemberID"
        static let teamID = "teamID"
        static let role = "role"
        static let joinedAt = "joinedAt"
    }

    enum SportEvent {
        static let recordType = "SportEvent"
        static let title = "title"
        static let sport = "sport"
        static let location = "location"
        static let street = "street"
        static let zip = "zip"
        static let city = "city"
        static let country = "country"
        static let startDate = "startDate"
        static let endDate = "endDate"
        static let notes = "notes"
        static let createdBy = "createdBy"
        static let createdAt = "createdAt"
        static let teamIDs = "teamIDs"
    }

    enum Training {
        static let recordType = "Training"
        static let title = "title"
        static let sport = "sport"
        static let location = "location"
        static let street = "street"
        static let zip = "zip"
        static let city = "city"
        static let country = "country"
        static let startDate = "startDate"
        static let endDate = "endDate"
        static let durationMinutes = "durationMinutes"
        static let focusArea = "focusArea"
        static let status = "status"
        static let notes = "notes"
        static let createdBy = "createdBy"
        static let createdAt = "createdAt"
        static let teamIDs = "teamIDs"
    }

    /// One local `Attendance` model, two CKRecord types kept distinct for
    /// backward compatibility with already-synced data — see
    /// `CloudKitSync.pushAttendance`'s doc comment.
    enum Attendance {
        static let trainingRecordType = "TrainingAttendance"
        static let tournamentRecordType = "TournamentAttendance"
        static let trainingID = "trainingID"
        static let tournamentID = "tournamentID"
        static let membershipID = "membershipID"
        static let attended = "attended"
        static let recordedAt = "recordedAt"
        static let praeAmount = "praeAmount"
    }

    enum Tournament {
        static let recordType = "Tournament"
        static let title = "title"
        /// Old field name, still written alongside `title` for one release
        /// cycle of compat — see `CloudKitSync.pushTournament`'s doc comment.
        static let nameCompat = "name"
        static let sport = "sport"
        static let location = "location"
        /// Old field name, still written alongside `location` — see `nameCompat` above.
        static let venueCompat = "venue"
        static let street = "street"
        static let zip = "zip"
        static let city = "city"
        static let country = "country"
        static let startDate = "startDate"
        static let endDate = "endDate"
        static let maxTeams = "maxTeams"
        static let status = "status"
        static let notes = "notes"
        static let createdBy = "createdBy"
        static let createdAt = "createdAt"
        static let teamIDs = "teamIDs"
    }

    enum EventParticipation {
        static let recordType = "EventParticipation"
        static let userID = "userID"
        static let eventID = "eventID"
        static let status = "status"
        static let registeredAt = "registeredAt"
    }

    enum UserIdentity {
        static let recordType = "UserIdentity"
        static let firstName = "firstName"
        static let lastName = "lastName"
        static let role = "role"
        static let isGrazerVSCMember = "isGrazerVSCMember"
        static let isRoot = "isRoot"
        /// Opaque token gating this user's read-only webcal calendar feed
        /// (architecture-review.md §5 P2 — served by clubmembersapi's
        /// `/calendar/:token` route, deliberately outside its Basic Auth
        /// gate since a webcal subscription can't present a login prompt in
        /// most calendar clients). Not a secret in the security sense — the
        /// feed only ever exposes training/tournament schedule data this
        /// user could already see in the app — just unguessable enough that
        /// stumbling onto someone else's feed isn't realistic. Empty until
        /// the user generates one (AccountView); regenerable to invalidate
        /// a leaked link.
        static let calendarToken = "calendarToken"
    }

    /// The app-side model is `Member` (renamed 2026-08-01), but the CKRecord
    /// type stays the historical "ClubMember" string for wire compatibility
    /// with already-synced production data — see `CloudKitSync.swift`'s top
    /// doc comment.
    /// Wraps the shared `ClubSchema.MemberField`/`ClubMemberRecord` (Phase 9,
    /// audit.md Architecture Finding 5) instead of declaring its own field
    /// strings — the same source of truth RootCLI's `MemberRecord` uses, so
    /// the two can't independently drift the way they already had to be
    /// hand-reconciled twice (cerebrum.md's 2026-07-18/2026-07-30 entries).
    enum ClubMember {
        static let recordType = ClubMemberRecord.recordType
        static let firstName = MemberField.firstName.rawValue
        static let lastName = MemberField.lastName.rawValue
        static let street = MemberField.street.rawValue
        static let zip = MemberField.zip.rawValue
        static let city = MemberField.city.rawValue
        static let country = MemberField.country.rawValue
        static let email = MemberField.email.rawValue
        static let phone = MemberField.phone.rawValue
        static let memberNumber = MemberField.memberNumber.rawValue
        static let joinedAt = MemberField.joinedAt.rawValue
        static let notes = MemberField.notes.rawValue
        static let gender = MemberField.gender.rawValue
        static let title = MemberField.title.rawValue
        static let birthDate = MemberField.birthDate.rawValue
        static let sportId = MemberField.sportId.rawValue
        static let svnr = MemberField.svnr.rawValue
        static let iban = MemberField.iban.rawValue
        static let lastMedicalExamination = MemberField.lastMedicalExamination.rawValue
        static let defaultFunction = MemberField.defaultFunction.rawValue
        static let memberOfGVSC = MemberField.memberOfGVSC.rawValue
    }

    enum EventImage {
        static let recordType = "EventImage"
        static let uploadedBy = "uploadedBy"
        static let uploadedAt = "uploadedAt"
        static let eventID = "eventID"
        static let asset = "asset"
        /// Pre-refactor records carried the FK under one of these instead of
        /// `eventID` — pull-only fallback, see `CloudKitSync.pullEventImages`.
        static let trainingIDCompat = "trainingID"
        static let tournamentIDCompat = "tournamentID"
    }

    enum ExpenseReceipt {
        static let recordType = "ExpenseReceipt"
        static let uploadedBy = "uploadedBy"
        static let uploadedAt = "uploadedAt"
        static let note = "note"
        static let month = "month"
        static let year = "year"
        static let tournamentID = "tournamentID"
        static let asset = "asset"
    }

    enum TrainingFavorite {
        static let recordType = "TrainingFavorite"
        static let title = "title"
        static let sport = "sport"
        static let startHour = "startHour"
        static let startMinute = "startMinute"
        static let endHour = "endHour"
        static let endMinute = "endMinute"
        static let weekday = "weekday"
        static let location = "location"
        static let street = "street"
        static let zip = "zip"
        static let city = "city"
        static let country = "country"
        static let teamIDs = "teamIDs"
        static let lastUsedAt = "lastUsedAt"
    }

    enum RoleChangeLog {
        static let recordType = "RoleChangeLog"
        static let userID = "userID"
        static let oldRole = "oldRole"
        static let newRole = "newRole"
        static let changedBy = "changedBy"
        static let changedAt = "changedAt"
    }

    /// A pending/approved/rejected self-service roster edit — see
    /// `MemberChangeRequest`'s doc comment. Field names mirror `ClubMember`
    /// for the proposed-value fields, plus its own review-workflow fields.
    enum MemberChangeRequest {
        static let recordType = "MemberChangeRequest"
        static let memberID = "memberID"
        static let requestedBy = "requestedBy"
        static let requestedAt = "requestedAt"
        static let status = "status"
        static let reviewedBy = "reviewedBy"
        static let reviewedAt = "reviewedAt"
        static let firstName = "firstName"
        static let lastName = "lastName"
        static let title = "title"
        static let gender = "gender"
        static let birthDate = "birthDate"
        static let street = "street"
        static let zip = "zip"
        static let city = "city"
        static let country = "country"
        static let email = "email"
        static let phone = "phone"
        static let sportId = "sportId"
        static let svnr = "svnr"
        static let iban = "iban"
        static let lastMedicalExamination = "lastMedicalExamination"
    }
}
