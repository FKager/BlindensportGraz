/// Closed enum of every roster field, so RootCLI (`MemberRecord` in
/// RootCLI/Sources/RootCLICore/MemberRecord.swift) never hand-types field
/// names: renaming a case stops every old reference from compiling.
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
