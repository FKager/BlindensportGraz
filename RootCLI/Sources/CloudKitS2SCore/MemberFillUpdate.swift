import Foundation

/// Non-destructive counterpart to `MemberBulkImport.run` — fills in fields
/// that are currently blank on an existing roster entry instead of
/// overwriting the whole entry (which `MemberBulkImport` does, regardless of
/// whether the incoming value is empty). Matching is by firstName+lastName
/// (case/whitespace-insensitive), the same identity rule `Member.matches`
/// uses in the app (Models.swift) — this package has no access to `svnr`/
/// `sportId` as a more precise key since not every existing record carries one.
/// An input row with no matching existing record is created fresh (same as
/// `MemberBulkImport`), since there's nothing to preserve. `memberOfGVSC` is a
/// Bool with no "blank" state, so it's only ever set on creation (defaulting
/// true) — never touched by the fill-update path for an existing match.
public enum MemberFillUpdate {
    /// Protected fields are filled the same way (in `member_private`).
    public static func run(_ inputs: [MemberBulkInput], store: MemberStore,
                           updatedBy: UUID? = nil) async -> MemberBulkImportResult {
        var result = MemberBulkImportResult()

        let existingRecords: [MemberRecord]
        do {
            existingRecords = try await store.all(includePrivate: true)
        } catch {
            result.failed = inputs.count
            result.messages.append("Could not fetch existing members, aborting: \(error)")
            return result
        }

        func nameKey(_ first: String, _ last: String) -> String {
            (first.trimmingCharacters(in: .whitespaces) + "|" + last.trimmingCharacters(in: .whitespaces)).lowercased()
        }

        var byName: [String: MemberRecord] = [:]
        for record in existingRecords where !record.firstName.isEmpty && !record.lastName.isEmpty {
            byName[nameKey(record.firstName, record.lastName)] = record
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

            let key = nameKey(firstName, lastName)
            guard let existing = byName[key] else {
                var record = MemberBulkImport.record(from: input, id: UUID().uuidString,
                                                     firstName: firstName, lastName: lastName)
                record.privateData = input.privateData
                do {
                    try await store.save(record, writePrivate: !input.privateData.isEmpty, updatedBy: updatedBy)
                    // A later row with the same name fills this one instead
                    // of creating a second entry.
                    byName[key] = record
                    result.succeeded += 1
                    result.messages.append("Created \(fullName) (\(record.id)) — no existing match.")
                } catch {
                    result.failed += 1
                    result.messages.append("Failed to create \(fullName): \(error)")
                }
                continue
            }

            var record = existing
            var filled: [String] = []

            func fill(_ keyPath: WritableKeyPath<MemberRecord, String>, _ name: String, _ newValue: String?) {
                let trimmed = (newValue ?? "").trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty, record[keyPath: keyPath].isEmpty else { return }
                record[keyPath: keyPath] = trimmed
                filled.append(name)
            }
            func fill(_ keyPath: WritableKeyPath<MemberRecord, Date?>, _ name: String, _ newValue: Date?) {
                guard let newValue, record[keyPath: keyPath] == nil else { return }
                record[keyPath: keyPath] = newValue
                filled.append(name)
            }

            fill(\.street, "street", input.street)
            fill(\.zip, "zip", input.zip)
            fill(\.city, "city", input.city)
            fill(\.country, "country", input.country)
            fill(\.email, "email", input.email)
            fill(\.phone, "phone", input.phone)
            fill(\.memberNumber, "memberNumber", input.memberNumber)
            fill(\.notes, "notes", input.notes)
            fill(\.gender, "gender", input.gender)
            fill(\.title, "title", input.title)
            fill(\.sportId, "sportId", input.sportId)
            fill(\.defaultFunction, "defaultFunction", input.defaultFunction)
            let incomingPrivate = input.privateData
            fill(\.svnr, "svnr", incomingPrivate.svnr)
            fill(\.iban, "iban", incomingPrivate.iban)
            fill(\.birthDate, "birthDate", incomingPrivate.birthDate)
            fill(\.lastMedicalExamination, "lastMedicalExamination", incomingPrivate.lastMedicalExamination)

            guard !filled.isEmpty else {
                result.messages.append("No blank fields to fill for \(fullName) — already up to date.")
                continue
            }

            do {
                try await store.save(record, writePrivate: record.privateData != existing.privateData,
                                     updatedBy: updatedBy)
                // Later rows for the same member (duplicate names) build on
                // what this row just filled.
                byName[key] = record
                result.succeeded += 1
                result.messages.append("Filled \(fullName) (\(existing.id)): \(filled.joined(separator: ", "))")
            } catch {
                result.failed += 1
                result.messages.append("Failed to update \(fullName): \(error)")
            }
        }
        return result
    }
}
