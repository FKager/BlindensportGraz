import XCTest
import SwiftData
@testable import BlindensportGraz

final class TeilnehmerlisteExportTests: XCTestCase {

    /// Runs `body` on a background queue and fails (instead of hanging the whole
    /// test run forever) if it doesn't return within `timeout` seconds — this is
    /// the whole point: a genuine infinite loop in the export path should show up
    /// here as a clear test failure, not as this test process hanging too.
    private func runWithTimeout(_ timeout: TimeInterval, _ label: String, _ body: @escaping () throws -> Void) {
        let sem = DispatchSemaphore(value: 0)
        var caught: Error?
        let start = Date()
        DispatchQueue.global().async {
            do { try body() } catch { caught = error }
            sem.signal()
        }
        let result = sem.wait(timeout: .now() + timeout)
        let elapsed = Date().timeIntervalSince(start)
        if result == .timedOut {
            XCTFail("\(label): TIMED OUT after \(timeout)s — likely infinite loop/hang")
            return
        }
        if let caught {
            XCTFail("\(label): threw \(caught)")
            return
        }
        print("\(label): completed in \(String(format: "%.3f", elapsed))s")
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            User.self, SportEvent.self, Tournament.self, Training.self, Team.self,
            TeamMembership.self, EventParticipation.self, ClubMember.self,
            EventImage.self, TrainingAttendance.self, TournamentAttendance.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func makeMemberships(_ context: ModelContext, team: Team, names: [(String, String, String)]) -> [TeamMembership] {
        names.map { first, last, address in
            let member = ClubMember(firstName: first, lastName: last, address: address)
            context.insert(member)
            let membership = TeamMembership(clubMember: member, team: team)
            context.insert(membership)
            return membership
        }
    }

    /// A representative spread of realistic German/Austrian names — umlauts, ß,
    /// hyphenated surnames, "von"/"van" particles, apostrophes, varying lengths —
    /// covering the kind of real attendee data this export actually sees, at
    /// several attendee counts including right at and past the 25-row form limit.
    private let realisticNames: [(String, String, String)] = [
        ("Andreas", "Müller", "Hauptstraße 12, 8010 Graz"),
        ("Bärbel", "Groß", "Schönbrunngasse 3, 8020 Graz"),
        ("Özlem", "Yılmaz", "Grazbachgasse 5, 8010 Graz"),
        ("Sepp", "Huber-Maier", "Am Grünanger 7, 8045 Graz"),
        ("Wolfgang", "Straßer", "Elisabethstraße 45, 8010 Graz"),
        ("Gudrun", "d'Angelo", "Jakominiplatz 1, 8010 Graz"),
        ("Franz", "Kager", "Am Kirchplatz 2, 8010 Graz"),
        ("Sigrid", "Weiß", "Lendplatz 9, 8020 Graz"),
        ("Reinhard", "Öller", "Neutorgasse 21, 8010 Graz"),
        ("Christa", "Übleis", "Klosterwiesgasse 14, 8010 Graz"),
        ("Hans-Peter", "Aigner", "Conrad-von-Hötzendorf-Straße 88, 8010 Graz"),
        ("Ingrid", "Schmölzer", "Kärntner Straße 300, 8054 Graz"),
        ("Kurt", "Pötzl", "Triesterstraße 15, 8020 Graz"),
        ("Waltraud", "Zöhrer", "Mariahilferstraße 5, 8020 Graz"),
        ("Günther", "Bäck", "Merangasse 70, 8010 Graz"),
        ("Elfriede", "Ćosić", "Grabenstraße 44, 8010 Graz"),
        ("Rudolf", "Niederl", "Petersgasse 120, 8010 Graz"),
        ("Traude", "Fürst", "Plüddemanngasse 45, 8010 Graz"),
        ("Herbert", "Sattler", "Body & Mind, 8010 Graz"),
        ("Roswitha", "König", "Am Fröbelpark 3, 8020 Graz"),
        ("Alfred", "Steinmüller", "Peter-Rosegger-Straße 22, 8010 Graz"),
        ("Brigitte", "Weißensteiner", "Am Ölberg 6, 8010 Graz"),
        ("Manfred", "Ölzant", "Grabenweg 11, 8045 Graz"),
        ("Erna", "Grössl", "Am Schönberg 8, 8045 Graz"),
        ("Fritz", "Häupl", "Bahnhofgürtel 55, 8020 Graz"),
        ("Liesl", "Süß", "Feuerbachgasse 5, 8010 Graz"),
        ("Otto", "Wührer", "Wienerstraße 78, 8010 Graz"),
        ("Anneliese", "Grünwald-Öfner", "Am Wetterkogel 3, 8045 Graz"),
        ("Karl-Heinz", "Dörflinger", "Hasnerplatz 4, 8010 Graz"),
        ("Mizzi", "O'Brien-Weiß", "Radetzkystraße 12, 8010 Graz")
    ]

    private func context(_ count: Int, timeout: TimeInterval = 8) throws -> String {
        let container = try makeContainer()
        let context = ModelContext(container)
        let team = Team(name: "Torball 1", sport: "Torball")
        context.insert(team)
        let subset = Array(realisticNames.prefix(count))
        let memberships = makeMemberships(context, team: team, names: subset)
        let ctx = TeilnehmerlisteContext(
            betrifft: "Training Torball – Übungseinheit Nr. 42",
            ort: "Sporthalle Graz-Süd, Körösistraße",
            startDate: Date(timeIntervalSince1970: 1_770_000_000),
            endDate: Date(timeIntervalSince1970: 1_770_086_400),
            attendedMemberships: memberships
        )
        var producedURL: URL?
        runWithTimeout(timeout, "export with \(count) attendees") {
            producedURL = try TeilnehmerlisteExporter.export(context: ctx)
        }
        guard let producedURL else { return "no url produced" }
        defer { try? FileManager.default.removeItem(at: producedURL) }
        let data = try Data(contentsOf: producedURL)
        return "\(data.count) bytes"
    }

    func testExportVariousAttendeeCounts() throws {
        for count in [0, 1, 2, 5, 12, 24, 25, 26, 30] {
            let info = try context(count)
            print("count=\(count): \(info)")
        }
    }

    /// Bundles ALL 30 realistic names in one go (form caps at 25 rows, so this
    /// also exercises the maxRows-truncation path) — closest match to a real
    /// club roster with a big turnout.
    func testExportFullRoster() throws {
        _ = try context(realisticNames.count, timeout: 10)
    }
}
