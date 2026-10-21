import Foundation
import ClubSchema

/// `MemberRecord` is now a thin alias over the shared `ClubMemberRecord`
/// (Shared/ClubSchema — audit.md Architecture Finding 5), not an
/// independent field-shape declaration. `rootcli import-members` uses this
/// alias (webadmin/'s Java `MemberRecord` mirrors the same JSON), so the tools —
/// and the app's own `Member` model — stay in
/// lockstep with one source of truth instead of drifting apart the way a
/// field split already required manual lockstep fixes twice (see
/// cerebrum.md's 2026-07-18/2026-07-30 entries).
///
public typealias MemberRecord = ClubMemberRecord

extension ClubMemberRecord {
    /// The protected fields carried by this value (from an API body or an
    /// import row); stored via `MemberPrivateStore` (member_private).
    public var privateData: MemberPrivate {
        get { MemberPrivate(svnr: svnr, iban: iban, birthDate: birthDate, lastMedicalExamination: lastMedicalExamination) }
        set {
            svnr = newValue.svnr
            iban = newValue.iban
            birthDate = newValue.birthDate
            lastMedicalExamination = newValue.lastMedicalExamination
        }
    }
}
