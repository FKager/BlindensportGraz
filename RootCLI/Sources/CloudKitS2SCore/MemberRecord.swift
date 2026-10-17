import Foundation
import ClubSchema

/// `MemberRecord` is now a thin alias over the shared `ClubMemberRecord`
/// (Shared/ClubSchema — audit.md Architecture Finding 5), not an
/// independent field-shape declaration. `rootcli import-members` uses this
/// alias (webadmin/'s Java `MemberRecord` mirrors the same JSON), so the tools —
/// and the app's own `Member` model/`CKSchema.ClubMember` — stay in
/// lockstep with one source of truth instead of drifting apart the way a
/// field split already required manual lockstep fixes twice (see
/// cerebrum.md's 2026-07-18/2026-07-30 entries).
///
/// CKRecordDTO conversion (`init?(dto:)`/`ckFields`) stays here, not in the
/// shared package — `CKRecordDTO` and the CloudKit Web Services field-dict
/// wire convention (`["value": ..., "type": ...]`) are RootCLI-specific,
/// and the shared package must stay usable from the iOS app target too,
/// which has no use for either.
public typealias MemberRecord = ClubMemberRecord

extension ClubMemberRecord {
    public init?(dto: CKRecordDTO) {
        guard dto.recordType == ClubMemberRecord.recordType else { return nil }
        // Missing on records written before this flag existed — default true,
        // matching every pre-existing roster entry's implicit membership.
        // (Can't use `dto.boolField` here: it defaults absent fields to
        // `false`, which is the wrong default for this particular flag.)
        let memberOfGVSC: Bool
        if let raw = (dto.fields[MemberField.memberOfGVSC.rawValue] as? [String: Any])?["value"] as? NSNumber {
            memberOfGVSC = raw.boolValue
        } else {
            memberOfGVSC = true
        }
        self.init(
            id: dto.recordName,
            firstName: dto.stringField(MemberField.firstName.rawValue) ?? "",
            lastName: dto.stringField(MemberField.lastName.rawValue) ?? "",
            street: dto.stringField(MemberField.street.rawValue) ?? "",
            zip: dto.stringField(MemberField.zip.rawValue) ?? "",
            city: dto.stringField(MemberField.city.rawValue) ?? "",
            country: dto.stringField(MemberField.country.rawValue) ?? "",
            email: dto.stringField(MemberField.email.rawValue) ?? "",
            phone: dto.stringField(MemberField.phone.rawValue) ?? "",
            memberNumber: dto.stringField(MemberField.memberNumber.rawValue) ?? "",
            joinedAt: dto.dateField(MemberField.joinedAt.rawValue) ?? Date(),
            notes: dto.stringField(MemberField.notes.rawValue) ?? "",
            gender: dto.stringField(MemberField.gender.rawValue) ?? "",
            title: dto.stringField(MemberField.title.rawValue) ?? "",
            birthDate: dto.dateField(MemberField.birthDate.rawValue),
            sportId: dto.stringField(MemberField.sportId.rawValue) ?? "",
            svnr: dto.stringField(MemberField.svnr.rawValue) ?? "",
            iban: dto.stringField(MemberField.iban.rawValue) ?? "",
            lastMedicalExamination: dto.dateField(MemberField.lastMedicalExamination.rawValue),
            defaultFunction: dto.stringField(MemberField.defaultFunction.rawValue) ?? "",
            memberOfGVSC: memberOfGVSC
        )
    }

    /// Field dict as CloudKit Web Services expects it for a create/update
    /// (`records/modify`). Excludes `id`, which is the CKRecord name, not a
    /// field, and the protected fields (svnr, iban, birthDate,
    /// lastMedicalExamination): CloudKit's public database is readable by
    /// every app install, so those live only in Supabase — see
    /// `MemberPrivateStore`.
    public var ckFields: [String: Any] {
        let fields: [String: Any] = [
            MemberField.firstName.rawValue: ["value": firstName],
            MemberField.lastName.rawValue: ["value": lastName],
            MemberField.street.rawValue: ["value": street],
            MemberField.zip.rawValue: ["value": zip],
            MemberField.city.rawValue: ["value": city],
            MemberField.country.rawValue: ["value": country],
            MemberField.email.rawValue: ["value": email],
            MemberField.phone.rawValue: ["value": phone],
            MemberField.memberNumber.rawValue: ["value": memberNumber],
            MemberField.notes.rawValue: ["value": notes],
            MemberField.joinedAt.rawValue: ["value": Int64(joinedAt.timeIntervalSince1970 * 1000), "type": "TIMESTAMP"],
            MemberField.gender.rawValue: ["value": gender],
            MemberField.title.rawValue: ["value": title],
            MemberField.sportId.rawValue: ["value": sportId],
            MemberField.defaultFunction.rawValue: ["value": defaultFunction],
            MemberField.memberOfGVSC.rawValue: ["value": memberOfGVSC ? 1 : 0, "type": "INT64"]
        ]
        return fields
    }

    /// The protected fields carried by this value (from an API body or an
    /// import row); stored via `MemberPrivateStore`, never in CloudKit.
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
