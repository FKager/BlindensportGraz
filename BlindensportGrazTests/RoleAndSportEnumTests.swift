import XCTest
import SwiftData
@testable import BlindensportGraz

/// Coverage for the Phase 7 enum migration (audit.md Architecture Finding 3):
/// `AppRole` (User.role), `MembershipRole` (TeamMembership.role), and the
/// `Sport` normalization utility. Each fallback test feeds a deliberately
/// garbage/unrecognized raw string through `normalize` and confirms it lands
/// in the defined `.other(...)` case — never crashes, never silently drops
/// the original value — per this phase's own "never crash or silently drop
/// data" requirement. The round-trip tests mirror what `CloudKitSync`'s
/// push (`.rawValue`) / pull (`.normalize(...)`) actually do, without going
/// through `CloudKitSync.shared` itself (which touches a real `CKContainer`
/// and crashes unsigned test runs — see cerebrum.md's 2026-08-22 "never
/// call CloudKitSync from new tests" entry).
@available(iOS 26, *)
final class RoleAndSportEnumTests: XCTestCase {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            User.self, SportEvent.self, Tournament.self, Training.self, Team.self,
            TeamMembership.self, EventParticipation.self, Member.self,
            EventImage.self, Attendance.self, TrainingFavorite.self, RoleChangeLog.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [config])
    }

    // MARK: - Fallback normalization (one per affected model type)

    /// User.role — a garbage/legacy value must not crash and must not be
    /// silently coerced to a known case (which could accidentally grant or
    /// deny elevated access based on misread garbage).
    func testAppRoleNormalizeFallbackForGarbageValueRetainsOriginalText() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let user = User(email: "test@example.com", firstName: "Test", lastName: "User",
                         role: AppRole.normalize("SUPERADMIN_LEGACY_TYPO"))
        context.insert(user)
        try context.save()

        guard case .other(let raw) = user.role else {
            return XCTFail("expected .other fallback, got \(user.role)")
        }
        XCTAssertEqual(raw, "SUPERADMIN_LEGACY_TYPO")
        // An unrecognized role must never be treated as admin/coach.
        XCTAssertNotEqual(user.role, .admin)
        XCTAssertNotEqual(user.role, .coach)
    }

    /// TeamMembership.role — the actual confirmed-bug field (audit.md's
    /// cited `!["coach","assistant"].contains(role)` typo-prone check).
    func testMembershipRoleNormalizeFallbackForGarbageValueRetainsOriginalText() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let team = Team(name: "Test Team", sport: "Torball")
        context.insert(team)
        let membership = TeamMembership(team: team, role: MembershipRole.normalize("Übungsleiter"))
        context.insert(membership)
        try context.save()

        guard case .other(let raw) = membership.role else {
            return XCTFail("expected .other fallback, got \(membership.role)")
        }
        XCTAssertEqual(raw, "Übungsleiter")
        // Never crash and never silently classify garbage as a helper OR a
        // player — both isHelfer and == .player must be false.
        XCTAssertFalse(membership.role.isHelfer)
        XCTAssertNotEqual(membership.role, .player)
    }

    /// SportEvent/Training/Tournament all share the same `sport: String`
    /// field and the same `Sport.normalize` utility — garbage input must
    /// never crash `SportIcon`'s lookups and must retain the original text.
    func testSportNormalizeFallbackForGarbageValueRetainsOriginalText() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let garbageSport = "Unterwasserrugby"
        let event = SportEvent(title: "Test", sport: garbageSport, location: "Graz", startDate: .now, endDate: .now)
        context.insert(event)
        try context.save()

        let normalized = Sport.normalize(event.sport)
        guard case .other(let raw) = normalized else {
            return XCTFail("expected .other fallback, got \(normalized)")
        }
        XCTAssertEqual(raw, garbageSport)
        // Never crashes — SportIcon falls back to a generic symbol/color.
        XCTAssertEqual(SportIcon.symbolName(for: event.sport), "sportscourt.fill")
        XCTAssertFalse(SportIcon.hasCustomGlyph(for: event.sport))
    }

    // MARK: - Push/pull round-trip (mirrors CloudKitSync's own encode/decode,
    // without touching CloudKitSync.shared itself)

    func testAppRoleRawValueRoundTripsThroughNormalize() {
        for role: AppRole in [.member, .coach, .admin, .other("weird-legacy-value")] {
            // Mirrors CloudKitSync+UserIdentity.pushUserIdentity's `.rawValue`
            // write, then pullUserIdentities' `AppRole.normalize(...)` read.
            let wireValue = role.rawValue
            let decoded = AppRole.normalize(wireValue)
            XCTAssertEqual(decoded, role, "round-trip through rawValue/normalize must be lossless for \(role)")
        }
    }

    func testMembershipRoleRawValueRoundTripsThroughNormalize() {
        for role: MembershipRole in [.player, .coach, .assistant, .other("Übungsleiter")] {
            // Mirrors CloudKitSync+TeamMembership's push (`.rawValue`) / pull
            // (`MembershipRole.normalize(...)`) pair.
            let wireValue = role.rawValue
            let decoded = MembershipRole.normalize(wireValue)
            XCTAssertEqual(decoded, role, "round-trip through rawValue/normalize must be lossless for \(role)")
        }
    }
}
