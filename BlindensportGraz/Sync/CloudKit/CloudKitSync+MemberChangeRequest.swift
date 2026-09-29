import CloudKit
import SwiftData
import Foundation

extension CloudKitSync {
    func pushMemberChangeRequest(_ request: MemberChangeRequest) {
        let record = CKRecord(recordType: CKSchema.MemberChangeRequest.recordType, recordID: recordID(request.id))
        record[CKSchema.MemberChangeRequest.memberID] = request.memberID.uuidString
        record[CKSchema.MemberChangeRequest.requestedBy] = request.requestedBy
        record[CKSchema.MemberChangeRequest.requestedAt] = request.requestedAt
        record[CKSchema.MemberChangeRequest.status] = request.status
        record[CKSchema.MemberChangeRequest.reviewedBy] = request.reviewedBy
        record[CKSchema.MemberChangeRequest.reviewedAt] = request.reviewedAt
        record[CKSchema.MemberChangeRequest.firstName] = request.firstName
        record[CKSchema.MemberChangeRequest.lastName] = request.lastName
        record[CKSchema.MemberChangeRequest.title] = request.title
        record[CKSchema.MemberChangeRequest.gender] = request.gender
        record[CKSchema.MemberChangeRequest.birthDate] = request.birthDate
        record[CKSchema.MemberChangeRequest.street] = request.street
        record[CKSchema.MemberChangeRequest.zip] = request.zip
        record[CKSchema.MemberChangeRequest.city] = request.city
        record[CKSchema.MemberChangeRequest.country] = request.country
        record[CKSchema.MemberChangeRequest.email] = request.email
        record[CKSchema.MemberChangeRequest.phone] = request.phone
        record[CKSchema.MemberChangeRequest.sportId] = request.sportId
        record[CKSchema.MemberChangeRequest.svnr] = request.svnr
        record[CKSchema.MemberChangeRequest.iban] = request.iban
        record[CKSchema.MemberChangeRequest.lastMedicalExamination] = request.lastMedicalExamination
        save(record)
    }

    func pullMemberChangeRequests(modelContext: ModelContext) async {
        for record in await fetchAll(recordType: CKSchema.MemberChangeRequest.recordType) {
            guard let id = UUID(uuidString: record.recordID.recordName),
                  let memberIDString = record[CKSchema.MemberChangeRequest.memberID] as? String,
                  let memberID = UUID(uuidString: memberIDString) else { continue }
            let requestedBy = record[CKSchema.MemberChangeRequest.requestedBy] as? String ?? ""
            let requestedAt = record[CKSchema.MemberChangeRequest.requestedAt] as? Date ?? .now
            let status = record[CKSchema.MemberChangeRequest.status] as? String ?? MemberChangeRequest.pendingStatus
            let reviewedBy = record[CKSchema.MemberChangeRequest.reviewedBy] as? String ?? ""
            let reviewedAt = record[CKSchema.MemberChangeRequest.reviewedAt] as? Date
            let firstName = record[CKSchema.MemberChangeRequest.firstName] as? String ?? ""
            let lastName = record[CKSchema.MemberChangeRequest.lastName] as? String ?? ""
            let title = record[CKSchema.MemberChangeRequest.title] as? String ?? ""
            let gender = record[CKSchema.MemberChangeRequest.gender] as? String ?? ""
            let birthDate = record[CKSchema.MemberChangeRequest.birthDate] as? Date
            let street = record[CKSchema.MemberChangeRequest.street] as? String ?? ""
            let zip = record[CKSchema.MemberChangeRequest.zip] as? String ?? ""
            let city = record[CKSchema.MemberChangeRequest.city] as? String ?? ""
            let country = record[CKSchema.MemberChangeRequest.country] as? String ?? ""
            let email = record[CKSchema.MemberChangeRequest.email] as? String ?? ""
            let phone = record[CKSchema.MemberChangeRequest.phone] as? String ?? ""
            let sportId = record[CKSchema.MemberChangeRequest.sportId] as? String ?? ""
            let svnr = record[CKSchema.MemberChangeRequest.svnr] as? String ?? ""
            let iban = record[CKSchema.MemberChangeRequest.iban] as? String ?? ""
            let lastMedicalExamination = record[CKSchema.MemberChangeRequest.lastMedicalExamination] as? Date

            var descriptor = FetchDescriptor<MemberChangeRequest>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            if let existing = try? modelContext.fetch(descriptor).first {
                existing.memberID = memberID
                existing.requestedBy = requestedBy
                existing.requestedAt = requestedAt
                existing.status = status
                existing.reviewedBy = reviewedBy
                existing.reviewedAt = reviewedAt
                existing.firstName = firstName
                existing.lastName = lastName
                existing.title = title
                existing.gender = gender
                existing.birthDate = birthDate
                existing.street = street
                existing.zip = zip
                existing.city = city
                existing.country = country
                existing.email = email
                existing.phone = phone
                existing.sportId = sportId
                existing.svnr = svnr
                existing.iban = iban
                existing.lastMedicalExamination = lastMedicalExamination
            } else {
                let request = MemberChangeRequest(
                    id: id, memberID: memberID, requestedBy: requestedBy, requestedAt: requestedAt,
                    status: status, reviewedBy: reviewedBy, reviewedAt: reviewedAt,
                    firstName: firstName, lastName: lastName, title: title, gender: gender, birthDate: birthDate,
                    street: street, zip: zip, city: city, country: country, email: email, phone: phone,
                    sportId: sportId, svnr: svnr, iban: iban, lastMedicalExamination: lastMedicalExamination
                )
                modelContext.insert(request)
            }
        }
    }
}
