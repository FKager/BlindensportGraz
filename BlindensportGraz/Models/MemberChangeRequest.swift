import Foundation
import SwiftData

/// A club member's own edit to their roster ("Vereinsdaten") data, awaiting
/// admin review — architecture-review.md §5 P2 ("member self-service
/// profile + admin approval queue"). Before this, `MyMemberView` wrote
/// straight to the live `Member` record (including SVNR/IBAN) with no
/// review at all. `RoleChangeLog` is the precedent for this app's
/// propose-then-apply-with-an-audit-trail shape.
///
/// Holds a full proposed snapshot of every self-editable `Member` field —
/// the same set `MyMemberView`'s Form edits, i.e. everything except the
/// admin-only `memberNumber`/`joinedAt`/`notes`/`defaultFunction`/
/// `memberOfGVSC` (see that view's section comments) — not a diff.
/// `apply(to:)` is then just "copy every field onto the real Member", with
/// no separate diff/merge logic to keep in sync as fields are added.
@Model
final class MemberChangeRequest {
    @Attribute(.unique) var id: UUID = UUID()
    var memberID: UUID = UUID()
    /// The requesting User's `id.uuidString`.
    var requestedBy: String = ""
    var requestedAt: Date = Date.now
    var status: String = MemberChangeRequest.pendingStatus
    /// The reviewing admin's `id.uuidString`; empty while pending.
    var reviewedBy: String = ""
    var reviewedAt: Date?

    var firstName: String = ""
    var lastName: String = ""
    var title: String = ""
    var gender: String = ""
    var birthDate: Date?
    var street: String = ""
    var zip: String = ""
    var city: String = ""
    var country: String = ""
    var email: String = ""
    var phone: String = ""
    var sportId: String = ""
    var svnr: String = ""
    var iban: String = ""
    var lastMedicalExamination: Date?
    // Beitrittserklärung fields (see Member). The contact-level ones travel in
    // member_change_requests; disability/consents are protected and go
    // through member_private_requests like svnr/iban.
    var membershipType: String = ""
    var citizenship: String = ""
    var mobile: String = ""
    var guardianFirstName: String = ""
    var guardianLastName: String = ""
    var guardianStreet: String = ""
    var guardianZip: String = ""
    var guardianCity: String = ""
    var guardianPhone: String = ""
    var guardianMobile: String = ""
    var guardianEmail: String = ""
    var disabilityType: String = ""
    var disabilityClass: String = ""
    var disabilityCause: String = ""
    var consentDataTransfer: Bool?
    var consentPhotos: Bool?

    init(id: UUID = UUID(), memberID: UUID, requestedBy: String, requestedAt: Date = .now,
         status: String = MemberChangeRequest.pendingStatus, reviewedBy: String = "", reviewedAt: Date? = nil,
         firstName: String, lastName: String, title: String, gender: String, birthDate: Date?,
         street: String, zip: String, city: String, country: String, email: String, phone: String,
         sportId: String, svnr: String, iban: String, lastMedicalExamination: Date?) {
        self.id = id
        self.memberID = memberID
        self.requestedBy = requestedBy
        self.requestedAt = requestedAt
        self.status = status
        self.reviewedBy = reviewedBy
        self.reviewedAt = reviewedAt
        self.firstName = firstName
        self.lastName = lastName
        self.title = title
        self.gender = gender
        self.birthDate = birthDate
        self.street = street
        self.zip = zip
        self.city = city
        self.country = country
        self.email = email
        self.phone = phone
        self.sportId = sportId
        self.svnr = svnr
        self.iban = iban
        self.lastMedicalExamination = lastMedicalExamination
    }
}

nonisolated extension MemberChangeRequest {
    static let pendingStatus = "pending"
    static let approvedStatus = "approved"
    static let rejectedStatus = "rejected"

    /// Seeds a new, not-yet-inserted request from `member`'s CURRENT field
    /// values — `MyMemberView` binds its Form directly to one of these
    /// (`@Bindable`, exactly like it used to bind to `member` itself), so
    /// editing feels identical; the live `member` is never touched until
    /// this gets approved.
    static func snapshot(of member: Member, requestedBy: String) -> MemberChangeRequest {
        let request = MemberChangeRequest(
            memberID: member.id, requestedBy: requestedBy,
            firstName: member.firstName, lastName: member.lastName, title: member.title,
            gender: member.gender, birthDate: member.birthDate, street: member.street,
            zip: member.zip, city: member.city, country: member.country, email: member.email,
            phone: member.phone, sportId: member.sportId, svnr: member.svnr, iban: member.iban,
            lastMedicalExamination: member.lastMedicalExamination
        )
        request.copyApplicationFields(from: member)
        return request
    }

    /// The Beitrittserklärung fields, from the live roster entry.
    func copyApplicationFields(from member: Member) {
        membershipType = member.membershipType
        citizenship = member.citizenship
        mobile = member.mobile
        guardianFirstName = member.guardianFirstName
        guardianLastName = member.guardianLastName
        guardianStreet = member.guardianStreet
        guardianZip = member.guardianZip
        guardianCity = member.guardianCity
        guardianPhone = member.guardianPhone
        guardianMobile = member.guardianMobile
        guardianEmail = member.guardianEmail
        disabilityType = member.disabilityType
        disabilityClass = member.disabilityClass
        disabilityCause = member.disabilityCause
        consentDataTransfer = member.consentDataTransfer
        consentPhotos = member.consentPhotos
    }

    /// True if any proposed field differs from `member`'s current value —
    /// `MyMemberView` only submits when this is true, so opening the form
    /// and tapping "Fertig" without changing anything never creates a
    /// no-op pending request.
    func differs(from member: Member) -> Bool {
        firstName != member.firstName || lastName != member.lastName || title != member.title ||
            gender != member.gender || birthDate != member.birthDate || street != member.street ||
            zip != member.zip || city != member.city || country != member.country ||
            email != member.email || phone != member.phone || sportId != member.sportId ||
            svnr != member.svnr || iban != member.iban || lastMedicalExamination != member.lastMedicalExamination ||
            membershipType != member.membershipType || citizenship != member.citizenship || mobile != member.mobile ||
            guardianFirstName != member.guardianFirstName || guardianLastName != member.guardianLastName ||
            guardianStreet != member.guardianStreet || guardianZip != member.guardianZip ||
            guardianCity != member.guardianCity || guardianPhone != member.guardianPhone ||
            guardianMobile != member.guardianMobile || guardianEmail != member.guardianEmail ||
            disabilityType != member.disabilityType || disabilityClass != member.disabilityClass ||
            disabilityCause != member.disabilityCause || consentDataTransfer != member.consentDataTransfer ||
            consentPhotos != member.consentPhotos
    }

    /// Copies every proposed field onto `member` — the entire effect of
    /// approving a request. Caller persists `member` and marks `self`
    /// approved separately (see `MemberChangeRequestService.approve`).
    ///
    /// The protected fields (SVNR, IBAN, birth date, medical exam) are not
    /// part of the synced request row: on a reviewer's device they are only
    /// a seed copied from the local `Member`, which may still be blank or
    /// stale. Pass `includingPrivate: true` only when they come from a real
    /// proposal (`member_private_requests`) or the proposer's own snapshot —
    /// otherwise approving would wipe the member's protected data.
    func apply(to member: Member, includingPrivate: Bool) {
        member.firstName = firstName
        member.lastName = lastName
        member.title = title
        member.gender = gender
        member.street = street
        member.zip = zip
        member.city = city
        member.country = country
        member.email = email
        member.phone = phone
        member.sportId = sportId
        member.membershipType = membershipType
        member.citizenship = citizenship
        member.mobile = mobile
        member.guardianFirstName = guardianFirstName
        member.guardianLastName = guardianLastName
        member.guardianStreet = guardianStreet
        member.guardianZip = guardianZip
        member.guardianCity = guardianCity
        member.guardianPhone = guardianPhone
        member.guardianMobile = guardianMobile
        member.guardianEmail = guardianEmail
        guard includingPrivate else { return }
        member.svnr = svnr
        member.iban = iban
        member.birthDate = birthDate
        member.lastMedicalExamination = lastMedicalExamination
        member.disabilityType = disabilityType
        member.disabilityClass = disabilityClass
        member.disabilityCause = disabilityCause
        member.consentDataTransfer = consentDataTransfer
        member.consentPhotos = consentPhotos
    }
}
