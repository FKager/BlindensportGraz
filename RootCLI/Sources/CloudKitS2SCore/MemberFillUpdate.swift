import Foundation

/// Non-destructive counterpart to `MemberBulkImport.run` — fills in fields
/// that are currently blank on an existing `Member` record instead of
/// overwriting the whole record (`createOrReplaceRecord`/forceReplace, which
/// `MemberBulkImport` uses, always clobbers every field regardless of
/// whether the incoming value is empty). Matching is by firstName+lastName
/// (case/whitespace-insensitive), the same identity rule `Member.matches`
/// uses in the app (Models.swift) — this package has no access to `svnr`/
/// `sportId` as a more precise key since not every existing record carries one.
/// An input row with no matching existing record is created fresh (same as
/// `MemberBulkImport`), since there's nothing to preserve. `memberOfGVSC` is a
/// Bool with no "blank" state, so it's only ever set on creation (defaulting
/// true) — never touched by the fill-update path for an existing match.
public enum MemberFillUpdate {
    public static func run(_ inputs: [MemberBulkInput], client: CloudKitS2SClient) async -> MemberBulkImportResult {
        var result = MemberBulkImportResult()

        let existingRecords: [CKRecordDTO]
        do {
            existingRecords = try await client.queryRecords(recordType: "ClubMember")
        } catch {
            result.failed = inputs.count
            result.messages.append("Could not fetch existing Member records, aborting: \(error)")
            return result
        }

        func nameKey(_ first: String, _ last: String) -> String {
            (first.trimmingCharacters(in: .whitespaces) + "|" + last.trimmingCharacters(in: .whitespaces)).lowercased()
        }

        var byName: [String: CKRecordDTO] = [:]
        for record in existingRecords {
            let first = record.stringField("firstName") ?? ""
            let last = record.stringField("lastName") ?? ""
            guard !first.isEmpty, !last.isEmpty else { continue }
            byName[nameKey(first, last)] = record
        }

        for input in inputs {
            let firstName = (input.firstName ?? "").trimmingCharacters(in: .whitespaces)
            let lastName = (input.lastName ?? "").trimmingCharacters(in: .whitespaces)
            let fullName = [firstName, lastName].filter { !$0.isEmpty }.joined(separator: " ")
            guard !firstName.isEmpty, !lastName.isEmpty else {
                result.failed += 1
                result.messages.append("Skipped an entry with an empty firstName or lastName.")
                continue
            }

            guard let existing = byName[nameKey(firstName, lastName)] else {
                await create(input, firstName: firstName, lastName: lastName, fullName: fullName, client: client, result: &result)
                continue
            }

            var fieldsToSet: [String: Any] = [:]
            var filled: [String] = []

            func fillString(_ fieldName: String, _ newValue: String?) {
                guard let newValue else { return }
                let trimmed = newValue.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty, (existing.stringField(fieldName) ?? "").isEmpty else { return }
                fieldsToSet[fieldName] = CKFieldCoding.encode(trimmed)
                filled.append(fieldName)
            }
            func fillDate(_ fieldName: String, _ newValue: Date?) {
                guard let newValue, existing.dateField(fieldName) == nil else { return }
                fieldsToSet[fieldName] = CKFieldCoding.encode(newValue, type: "TIMESTAMP")
                filled.append(fieldName)
            }

            fillString("street", input.street)
            fillString("zip", input.zip)
            fillString("city", input.city)
            fillString("email", input.email)
            fillString("phone", input.phone)
            fillString("memberNumber", input.memberNumber)
            fillString("notes", input.notes)
            fillString("gender", input.gender)
            fillString("title", input.title)
            fillString("sportId", input.sportId)
            fillString("svnr", input.svnr)
            fillString("iban", input.iban)
            fillString("defaultFunction", input.defaultFunction)
            fillDate("birthDate", MemberBulkImport.parseFlexibleDate(input.birthDate))
            fillDate("lastMedicalExamination", MemberBulkImport.parseFlexibleDate(input.lastMedicalExamination))

            guard !fieldsToSet.isEmpty else {
                result.messages.append("No blank fields to fill for \(fullName) — already up to date.")
                continue
            }

            do {
                try await client.updateRecord(existing, fields: fieldsToSet)
                result.succeeded += 1
                result.messages.append("Filled \(fullName) (\(existing.recordName)): \(filled.joined(separator: ", "))")
            } catch {
                result.failed += 1
                result.messages.append("Failed to update \(fullName): \(error)")
            }
        }
        return result
    }

    private static func create(
        _ input: MemberBulkInput, firstName: String, lastName: String, fullName: String,
        client: CloudKitS2SClient, result: inout MemberBulkImportResult
    ) async {
        let recordName = UUID().uuidString
        let record = MemberRecord(
            id: recordName,
            firstName: firstName,
            lastName: lastName,
            street: input.street ?? "",
            zip: input.zip ?? "",
            city: input.city ?? "",
            email: input.email ?? "",
            phone: input.phone ?? "",
            memberNumber: input.memberNumber ?? "",
            joinedAt: MemberBulkImport.parseJoinedAt(input.joinedAt) ?? Date(),
            notes: input.notes ?? "",
            gender: input.gender ?? "",
            title: input.title ?? "",
            birthDate: MemberBulkImport.parseFlexibleDate(input.birthDate),
            sportId: input.sportId ?? "",
            svnr: input.svnr ?? "",
            iban: input.iban ?? "",
            lastMedicalExamination: MemberBulkImport.parseFlexibleDate(input.lastMedicalExamination),
            defaultFunction: input.defaultFunction ?? "",
            memberOfGVSC: input.memberOfGVSC ?? true
        )
        do {
            try await client.createOrReplaceRecord(recordType: "ClubMember", recordName: recordName, fields: record.ckFields)
            result.succeeded += 1
            result.messages.append("Created \(fullName) (\(recordName)) — no existing match.")
        } catch {
            result.failed += 1
            result.messages.append("Failed to create \(fullName): \(error)")
        }
    }
}
