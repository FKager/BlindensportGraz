import Foundation

/// Non-destructive counterpart to `ClubMemberBulkImport.run` — fills in fields
/// that are currently blank on an existing `ClubMember` record instead of
/// overwriting the whole record (`createOrReplaceRecord`/forceReplace, which
/// `ClubMemberBulkImport` uses, always clobbers every field regardless of
/// whether the incoming value is empty). Matching is by firstName+lastName
/// (case/whitespace-insensitive), the same identity rule `ClubMember.matches`
/// uses in the app (Models.swift) — this package has no access to `svnr`/
/// `sportId` as a more precise key since not every existing record carries one.
/// An input row with no matching existing record is created fresh (same as
/// `ClubMemberBulkImport`), since there's nothing to preserve.
public enum ClubMemberFillUpdate {
    public static func run(_ inputs: [ClubMemberBulkInput], client: CloudKitS2SClient) async -> ClubMemberBulkImportResult {
        var result = ClubMemberBulkImportResult()

        let existingRecords: [CKRecordDTO]
        do {
            existingRecords = try await client.queryRecords(recordType: "ClubMember")
        } catch {
            result.failed = inputs.count
            result.messages.append("Could not fetch existing ClubMember records, aborting: \(error)")
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
            fillDate("birthDate", ClubMemberBulkImport.parseFlexibleDate(input.birthDate))
            fillDate("lastMedicalExamination", ClubMemberBulkImport.parseFlexibleDate(input.lastMedicalExamination))

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
        _ input: ClubMemberBulkInput, firstName: String, lastName: String, fullName: String,
        client: CloudKitS2SClient, result: inout ClubMemberBulkImportResult
    ) async {
        let recordName = UUID().uuidString
        let record = ClubMemberRecord(
            id: recordName,
            firstName: firstName,
            lastName: lastName,
            street: input.street ?? "",
            zip: input.zip ?? "",
            city: input.city ?? "",
            email: input.email ?? "",
            phone: input.phone ?? "",
            memberNumber: input.memberNumber ?? "",
            joinedAt: ClubMemberBulkImport.parseJoinedAt(input.joinedAt) ?? Date(),
            notes: input.notes ?? "",
            gender: input.gender ?? "",
            title: input.title ?? "",
            birthDate: ClubMemberBulkImport.parseFlexibleDate(input.birthDate),
            sportId: input.sportId ?? "",
            svnr: input.svnr ?? "",
            iban: input.iban ?? "",
            lastMedicalExamination: ClubMemberBulkImport.parseFlexibleDate(input.lastMedicalExamination),
            defaultFunction: input.defaultFunction ?? ""
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
