import CloudKit
import SwiftData
import Foundation

extension CloudKitSync {
    func pushMember(_ member: Member) {
        // recordType stays the historical "ClubMember" string — see
        // CloudKitSync.swift's top doc comment.
        let record = CKRecord(recordType: CKSchema.ClubMember.recordType, recordID: recordID(member.id))
        record[CKSchema.ClubMember.firstName] = member.firstName
        record[CKSchema.ClubMember.lastName] = member.lastName
        record[CKSchema.ClubMember.street] = member.street
        record[CKSchema.ClubMember.zip] = member.zip
        record[CKSchema.ClubMember.city] = member.city
        record[CKSchema.ClubMember.country] = member.country
        record[CKSchema.ClubMember.email] = member.email
        record[CKSchema.ClubMember.phone] = member.phone
        record[CKSchema.ClubMember.memberNumber] = member.memberNumber
        record[CKSchema.ClubMember.joinedAt] = member.joinedAt
        record[CKSchema.ClubMember.notes] = member.notes
        record[CKSchema.ClubMember.gender] = member.gender
        record[CKSchema.ClubMember.title] = member.title
        record[CKSchema.ClubMember.birthDate] = member.birthDate
        record[CKSchema.ClubMember.sportId] = member.sportId
        record[CKSchema.ClubMember.svnr] = member.svnr
        record[CKSchema.ClubMember.iban] = member.iban
        record[CKSchema.ClubMember.lastMedicalExamination] = member.lastMedicalExamination
        record[CKSchema.ClubMember.defaultFunction] = member.defaultFunction
        record[CKSchema.ClubMember.memberOfGVSC] = member.memberOfGVSC
        save(record)
    }

    func deleteMember(_ id: UUID) {
        delete(recordType: CKSchema.ClubMember.recordType, id: id)
    }

    func pullMembers(modelContext: ModelContext) async {
        // recordType stays the historical "ClubMember" string — see
        // CloudKitSync.swift's top doc comment.
        for record in await fetchAll(recordType: CKSchema.ClubMember.recordType) {
            guard let id = UUID(uuidString: record.recordID.recordName) else { continue }
            let firstName = record[CKSchema.ClubMember.firstName] as? String ?? ""
            let lastName = record[CKSchema.ClubMember.lastName] as? String ?? ""
            let street = record[CKSchema.ClubMember.street] as? String ?? ""
            let zip = record[CKSchema.ClubMember.zip] as? String ?? ""
            let city = record[CKSchema.ClubMember.city] as? String ?? ""
            let country = record[CKSchema.ClubMember.country] as? String ?? ""
            let email = record[CKSchema.ClubMember.email] as? String ?? ""
            let phone = record[CKSchema.ClubMember.phone] as? String ?? ""
            let memberNumber = record[CKSchema.ClubMember.memberNumber] as? String ?? ""
            let joinedAt = record[CKSchema.ClubMember.joinedAt] as? Date ?? .now
            let notes = record[CKSchema.ClubMember.notes] as? String ?? ""
            let gender = record[CKSchema.ClubMember.gender] as? String ?? ""
            let title = record[CKSchema.ClubMember.title] as? String ?? ""
            let birthDate = record[CKSchema.ClubMember.birthDate] as? Date
            let sportId = record[CKSchema.ClubMember.sportId] as? String ?? ""
            let svnr = record[CKSchema.ClubMember.svnr] as? String ?? ""
            let iban = record[CKSchema.ClubMember.iban] as? String ?? ""
            let lastMedicalExamination = record[CKSchema.ClubMember.lastMedicalExamination] as? Date
            let defaultFunction = record[CKSchema.ClubMember.defaultFunction] as? String ?? ""
            // Missing on records pushed before this flag existed — default true,
            // matching every pre-existing roster entry's implicit membership.
            let memberOfGVSC = record[CKSchema.ClubMember.memberOfGVSC] as? Bool ?? true

            var descriptor = FetchDescriptor<Member>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            if let existing = try? modelContext.fetch(descriptor).first {
                existing.firstName = firstName
                existing.lastName = lastName
                existing.street = street
                existing.zip = zip
                existing.city = city
                existing.country = country
                existing.email = email
                existing.phone = phone
                existing.memberNumber = memberNumber
                existing.notes = notes
                existing.gender = gender
                existing.title = title
                existing.birthDate = birthDate
                existing.sportId = sportId
                existing.svnr = svnr
                existing.iban = iban
                existing.lastMedicalExamination = lastMedicalExamination
                existing.defaultFunction = defaultFunction
                existing.memberOfGVSC = memberOfGVSC
            } else {
                let member = Member(id: id, firstName: firstName, lastName: lastName, street: street,
                                     zip: zip, city: city, country: country, email: email, phone: phone,
                                     memberNumber: memberNumber, joinedAt: joinedAt, notes: notes,
                                     gender: gender, title: title, birthDate: birthDate, sportId: sportId,
                                     svnr: svnr, iban: iban, lastMedicalExamination: lastMedicalExamination,
                                     defaultFunction: defaultFunction, memberOfGVSC: memberOfGVSC)
                modelContext.insert(member)
            }
        }
    }
}
