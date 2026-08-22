import CloudKit
import SwiftData
import Foundation

/// SportEvent/Training/Tournament kept together in one file — they share the
/// same Swift class-hierarchy (Training/Tournament both subclass SportEvent),
/// splitting them into 3 files would mean either duplicating the shared
/// field set or introducing awkward cross-file coupling for no real benefit.
extension CloudKitSync {
    func pushEvent(_ event: SportEvent) {
        let record = CKRecord(recordType: CKSchema.SportEvent.recordType, recordID: recordID(event.id))
        record[CKSchema.SportEvent.title] = event.title
        record[CKSchema.SportEvent.sport] = event.sport
        record[CKSchema.SportEvent.location] = event.location
        record[CKSchema.SportEvent.street] = event.street
        record[CKSchema.SportEvent.zip] = event.zip
        record[CKSchema.SportEvent.city] = event.city
        record[CKSchema.SportEvent.country] = event.country
        record[CKSchema.SportEvent.startDate] = event.startDate
        record[CKSchema.SportEvent.endDate] = event.endDate
        record[CKSchema.SportEvent.notes] = event.notes
        record[CKSchema.SportEvent.createdBy] = event.createdBy
        record[CKSchema.SportEvent.createdAt] = event.createdAt
        record[CKSchema.SportEvent.teamIDs] = event.teams.map { $0.id.uuidString }
        save(record)
    }

    func pushTraining(_ training: Training) {
        let record = CKRecord(recordType: CKSchema.Training.recordType, recordID: recordID(training.id))
        record[CKSchema.Training.title] = training.title
        record[CKSchema.Training.sport] = training.sport
        record[CKSchema.Training.location] = training.location
        record[CKSchema.Training.street] = training.street
        record[CKSchema.Training.zip] = training.zip
        record[CKSchema.Training.city] = training.city
        record[CKSchema.Training.country] = training.country
        record[CKSchema.Training.startDate] = training.startDate
        record[CKSchema.Training.endDate] = training.endDate
        record[CKSchema.Training.durationMinutes] = training.durationMinutes
        record[CKSchema.Training.focusArea] = training.focusArea
        record[CKSchema.Training.notes] = training.notes
        record[CKSchema.Training.createdBy] = training.createdBy
        record[CKSchema.Training.createdAt] = training.createdAt
        record[CKSchema.Training.teamIDs] = training.teams.map { $0.id.uuidString }
        save(record)
    }

    /// Writes both the new (`title`/`location`) and old (`name`/`venue`) field
    /// names for one release cycle, so a still-updating old client editing the
    /// same record doesn't clobber the new fields with stale data mid-rollout.
    func pushTournament(_ tournament: Tournament) {
        let record = CKRecord(recordType: CKSchema.Tournament.recordType, recordID: recordID(tournament.id))
        record[CKSchema.Tournament.title] = tournament.title
        record[CKSchema.Tournament.nameCompat] = tournament.title
        record[CKSchema.Tournament.sport] = tournament.sport
        record[CKSchema.Tournament.location] = tournament.location
        record[CKSchema.Tournament.venueCompat] = tournament.location
        record[CKSchema.Tournament.street] = tournament.street
        record[CKSchema.Tournament.zip] = tournament.zip
        record[CKSchema.Tournament.city] = tournament.city
        record[CKSchema.Tournament.country] = tournament.country
        record[CKSchema.Tournament.startDate] = tournament.startDate
        record[CKSchema.Tournament.endDate] = tournament.endDate
        record[CKSchema.Tournament.maxTeams] = tournament.maxTeams
        record[CKSchema.Tournament.status] = tournament.status
        record[CKSchema.Tournament.notes] = tournament.notes
        record[CKSchema.Tournament.createdBy] = tournament.createdBy
        record[CKSchema.Tournament.createdAt] = tournament.createdAt
        record[CKSchema.Tournament.teamIDs] = tournament.teams.map { $0.id.uuidString }
        save(record)
    }

    func pullEvents(modelContext: ModelContext) async {
        for record in await fetchAll(recordType: CKSchema.SportEvent.recordType) {
            guard let id = UUID(uuidString: record.recordID.recordName) else { continue }
            let title = record[CKSchema.SportEvent.title] as? String ?? ""
            let sport = record[CKSchema.SportEvent.sport] as? String ?? ""
            let location = record[CKSchema.SportEvent.location] as? String ?? ""
            let street = record[CKSchema.SportEvent.street] as? String ?? ""
            let zip = record[CKSchema.SportEvent.zip] as? String ?? ""
            let city = record[CKSchema.SportEvent.city] as? String ?? ""
            let country = record[CKSchema.SportEvent.country] as? String ?? ""
            let startDate = record[CKSchema.SportEvent.startDate] as? Date ?? .now
            let endDate = record[CKSchema.SportEvent.endDate] as? Date ?? .now
            let notes = record[CKSchema.SportEvent.notes] as? String ?? ""
            let createdBy = record[CKSchema.SportEvent.createdBy] as? String ?? ""
            let createdAt = record[CKSchema.SportEvent.createdAt] as? Date ?? .now
            let teams = findTeams(record[CKSchema.SportEvent.teamIDs] as? [String] ?? [], modelContext: modelContext)

            var descriptor = FetchDescriptor<SportEvent>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            if let existing = try? modelContext.fetch(descriptor).first {
                existing.title = title
                existing.sport = sport
                existing.location = location
                existing.street = street
                existing.zip = zip
                existing.city = city
                existing.country = country
                existing.startDate = startDate
                existing.endDate = endDate
                existing.notes = notes
                existing.teams = teams
            } else {
                let event = SportEvent(id: id, title: title, sport: sport, location: location,
                                       street: street, zip: zip, city: city, country: country,
                                       startDate: startDate, endDate: endDate, notes: notes,
                                       createdBy: createdBy, createdAt: createdAt, teams: teams)
                modelContext.insert(event)
            }
        }
    }

    func pullTrainings(modelContext: ModelContext) async {
        for record in await fetchAll(recordType: CKSchema.Training.recordType) {
            guard let id = UUID(uuidString: record.recordID.recordName) else { continue }
            let title = record[CKSchema.Training.title] as? String ?? ""
            let sport = record[CKSchema.Training.sport] as? String ?? ""
            let location = record[CKSchema.Training.location] as? String ?? ""
            let street = record[CKSchema.Training.street] as? String ?? ""
            let zip = record[CKSchema.Training.zip] as? String ?? ""
            let city = record[CKSchema.Training.city] as? String ?? ""
            let country = record[CKSchema.Training.country] as? String ?? ""
            let startDate = record[CKSchema.Training.startDate] as? Date ?? .now
            let endDate = record[CKSchema.Training.endDate] as? Date ?? startDate
            let durationMinutes = record[CKSchema.Training.durationMinutes] as? Int ?? 90
            let focusArea = record[CKSchema.Training.focusArea] as? String ?? ""
            let notes = record[CKSchema.Training.notes] as? String ?? ""
            let createdBy = record[CKSchema.Training.createdBy] as? String ?? ""
            let createdAt = record[CKSchema.Training.createdAt] as? Date ?? .now
            let teams = findTeams(record[CKSchema.Training.teamIDs] as? [String] ?? [], modelContext: modelContext)

            var descriptor = FetchDescriptor<Training>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            if let existing = try? modelContext.fetch(descriptor).first {
                existing.title = title
                existing.sport = sport
                existing.location = location
                existing.street = street
                existing.zip = zip
                existing.city = city
                existing.country = country
                existing.startDate = startDate
                existing.endDate = endDate
                existing.durationMinutes = durationMinutes
                existing.focusArea = focusArea
                existing.notes = notes
                existing.teams = teams
            } else {
                let training = Training(id: id, title: title, sport: sport, location: location,
                                         street: street, zip: zip, city: city, country: country,
                                         startDate: startDate, durationMinutes: durationMinutes,
                                         focusArea: focusArea, notes: notes, createdBy: createdBy,
                                         createdAt: createdAt, teams: teams)
                training.endDate = endDate
                modelContext.insert(training)
            }
        }
    }

    func pullTournaments(modelContext: ModelContext) async {
        for record in await fetchAll(recordType: CKSchema.Tournament.recordType) {
            guard let id = UUID(uuidString: record.recordID.recordName) else { continue }
            let title = (record[CKSchema.Tournament.title] as? String) ?? (record[CKSchema.Tournament.nameCompat] as? String) ?? ""
            let sport = record[CKSchema.Tournament.sport] as? String ?? ""
            let location = (record[CKSchema.Tournament.location] as? String) ?? (record[CKSchema.Tournament.venueCompat] as? String) ?? ""
            let street = record[CKSchema.Tournament.street] as? String ?? ""
            let zip = record[CKSchema.Tournament.zip] as? String ?? ""
            let city = record[CKSchema.Tournament.city] as? String ?? ""
            let country = record[CKSchema.Tournament.country] as? String ?? ""
            let startDate = record[CKSchema.Tournament.startDate] as? Date ?? .now
            let endDate = record[CKSchema.Tournament.endDate] as? Date ?? .now
            let maxTeams = record[CKSchema.Tournament.maxTeams] as? Int ?? 8
            let status = record[CKSchema.Tournament.status] as? String ?? "planned"
            let notes = record[CKSchema.Tournament.notes] as? String ?? ""
            let createdBy = record[CKSchema.Tournament.createdBy] as? String ?? ""
            let createdAt = record[CKSchema.Tournament.createdAt] as? Date ?? .now
            let teams = findTeams(record[CKSchema.Tournament.teamIDs] as? [String] ?? [], modelContext: modelContext)

            var descriptor = FetchDescriptor<Tournament>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            if let existing = try? modelContext.fetch(descriptor).first {
                existing.title = title
                existing.sport = sport
                existing.location = location
                existing.street = street
                existing.zip = zip
                existing.city = city
                existing.country = country
                existing.startDate = startDate
                existing.endDate = endDate
                existing.maxTeams = maxTeams
                existing.status = status
                existing.notes = notes
                existing.teams = teams
            } else {
                let tournament = Tournament(id: id, title: title, sport: sport, location: location,
                                             street: street, zip: zip, city: city, country: country,
                                             startDate: startDate, endDate: endDate, maxTeams: maxTeams,
                                             status: status, notes: notes, createdBy: createdBy,
                                             createdAt: createdAt, teams: teams)
                modelContext.insert(tournament)
            }
        }
    }
}
