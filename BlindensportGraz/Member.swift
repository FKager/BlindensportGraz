import Foundation
import SwiftData

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
    var country: String = ""
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
         country: String = "",
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
        self.country = country
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

    /// Combines street/zip/city/country into one display line, e.g.
    /// "Hauptstraße 12, 8010 Graz, Österreich" — `country` only appears when
    /// set, so existing addresses without one still read exactly as before.
    /// Not stored, mirrors fullName's pattern — can't be used as a @Query sort key.
    var fullAddress: String {
        let zipCity = [zip, city].filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.joined(separator: " ")
        return [street, zipCity, country].filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.joined(separator: ", ")
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
