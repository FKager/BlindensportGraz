import CloudKit
import SwiftData
import Foundation

extension CloudKitSync {
    func pushTrainingFavorite(_ favorite: TrainingFavorite) {
        let record = CKRecord(recordType: CKSchema.TrainingFavorite.recordType, recordID: recordID(favorite.id))
        record[CKSchema.TrainingFavorite.title] = favorite.title
        record[CKSchema.TrainingFavorite.sport] = favorite.sport
        record[CKSchema.TrainingFavorite.startHour] = favorite.startHour
        record[CKSchema.TrainingFavorite.startMinute] = favorite.startMinute
        record[CKSchema.TrainingFavorite.endHour] = favorite.endHour
        record[CKSchema.TrainingFavorite.endMinute] = favorite.endMinute
        record[CKSchema.TrainingFavorite.weekday] = favorite.weekday
        record[CKSchema.TrainingFavorite.location] = favorite.location
        record[CKSchema.TrainingFavorite.street] = favorite.street
        record[CKSchema.TrainingFavorite.zip] = favorite.zip
        record[CKSchema.TrainingFavorite.city] = favorite.city
        record[CKSchema.TrainingFavorite.country] = favorite.country
        record[CKSchema.TrainingFavorite.teamIDs] = favorite.teams.map { $0.id.uuidString }
        record[CKSchema.TrainingFavorite.lastUsedAt] = favorite.lastUsedAt
        save(record)
    }

    func deleteTrainingFavorite(_ id: UUID) {
        delete(recordType: CKSchema.TrainingFavorite.recordType, id: id)
    }

    func pullTrainingFavorites(modelContext: ModelContext) async {
        for record in await fetchAll(recordType: CKSchema.TrainingFavorite.recordType) {
            guard let id = UUID(uuidString: record.recordID.recordName) else { continue }
            let title = record[CKSchema.TrainingFavorite.title] as? String ?? ""
            let sport = record[CKSchema.TrainingFavorite.sport] as? String ?? ""
            let startHour = record[CKSchema.TrainingFavorite.startHour] as? Int ?? 18
            let startMinute = record[CKSchema.TrainingFavorite.startMinute] as? Int ?? 0
            let endHour = record[CKSchema.TrainingFavorite.endHour] as? Int ?? 19
            let endMinute = record[CKSchema.TrainingFavorite.endMinute] as? Int ?? 30
            let weekday = record[CKSchema.TrainingFavorite.weekday] as? Int ?? 2
            let location = record[CKSchema.TrainingFavorite.location] as? String ?? ""
            let street = record[CKSchema.TrainingFavorite.street] as? String ?? ""
            let zip = record[CKSchema.TrainingFavorite.zip] as? String ?? ""
            let city = record[CKSchema.TrainingFavorite.city] as? String ?? ""
            let country = record[CKSchema.TrainingFavorite.country] as? String ?? ""
            let teams = findTeams(record[CKSchema.TrainingFavorite.teamIDs] as? [String] ?? [], modelContext: modelContext)
            let lastUsedAt = record[CKSchema.TrainingFavorite.lastUsedAt] as? Date ?? .now

            var descriptor = FetchDescriptor<TrainingFavorite>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            if let existing = try? modelContext.fetch(descriptor).first {
                existing.title = title
                existing.sport = sport
                existing.startHour = startHour
                existing.startMinute = startMinute
                existing.endHour = endHour
                existing.endMinute = endMinute
                existing.weekday = weekday
                existing.location = location
                existing.street = street
                existing.zip = zip
                existing.city = city
                existing.country = country
                existing.teams = teams
                existing.lastUsedAt = lastUsedAt
            } else {
                let favorite = TrainingFavorite(id: id, title: title, sport: sport,
                                                 startHour: startHour, startMinute: startMinute,
                                                 endHour: endHour, endMinute: endMinute,
                                                 weekday: weekday, location: location, street: street, zip: zip, city: city, country: country,
                                                 teams: teams, lastUsedAt: lastUsedAt)
                modelContext.insert(favorite)
            }
        }
    }
}
