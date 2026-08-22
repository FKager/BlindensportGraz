/// Closed enum of every field on the Member/ClubMember CKRecord — the
/// single source of truth both the app (via `CKSchema.ClubMember` in
/// BlindensportGraz/CKSchema.swift, which wraps these `rawValue`s) and
/// RootCLI (via `MemberRecord` in
/// RootCLI/Sources/CloudKitS2SCore/MemberRecord.swift) reference, instead
/// of each hand-typing the same field-name strings independently.
///
/// Renaming a case here is a REAL compile-time drift check: every reference
/// to the old case name, on either side of the app/RootCLI boundary, stops
/// compiling until it's updated — see this package's own doc comment for
/// how this phase demonstrated that live.
public enum MemberField: String, CaseIterable, Sendable {
    case firstName
    case lastName
    case street
    case zip
    case city
    case country
    case email
    case phone
    case memberNumber
    case joinedAt
    case notes
    case gender
    case title
    case birthDate
    case sportId
    case svnr
    case iban
    case lastMedicalExamination
    case defaultFunction
    case memberOfGVSC
}
