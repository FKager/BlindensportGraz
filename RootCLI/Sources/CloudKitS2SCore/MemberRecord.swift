import Foundation
import ClubSchema

/// `MemberRecord` is now a thin alias over the shared `ClubMemberRecord`
/// (Shared/ClubSchema — audit.md Architecture Finding 5), not an
/// independent field-shape declaration. `rootcli import-members` and
/// `clubmembersapi`'s REST routes both use this alias, so the two tools —
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
    /// field. `birthDate`/`lastMedicalExamination` are omitted entirely when
    /// nil, rather than sent as a null/placeholder value — CloudKit Web
    /// Services treats an absent key as "leave unset", matching `dateField`'s
    /// read-side handling of a missing key as nil.
    public var ckFields: [String: Any] {
        var fields: [String: Any] = [
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
            MemberField.svnr.rawValue: ["value": svnr],
            MemberField.iban.rawValue: ["value": iban],
            MemberField.defaultFunction.rawValue: ["value": defaultFunction],
            MemberField.memberOfGVSC.rawValue: ["value": memberOfGVSC ? 1 : 0, "type": "INT64"]
        ]
        if let birthDate {
            fields[MemberField.birthDate.rawValue] = ["value": Int64(birthDate.timeIntervalSince1970 * 1000), "type": "TIMESTAMP"]
        }
        if let lastMedicalExamination {
            fields[MemberField.lastMedicalExamination.rawValue] = ["value": Int64(lastMedicalExamination.timeIntervalSince1970 * 1000), "type": "TIMESTAMP"]
        }
        return fields
    }
}
