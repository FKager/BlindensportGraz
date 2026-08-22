import Foundation

/// Closed enum for `TeamMembership.role` (player/coach/assistant) —
/// audit.md Architecture Finding 3's actual confirmed bug: a free-text
/// `role` field let `TournamentsViews.swift`'s `!["coach","assistant"].contains(role)`-
/// style check silently include anything that wasn't literally one of those
/// two strings (including future typos) in "Sportler" filters that should
/// only ever match `.player`. See `AppRole` (User.swift's app-level
/// member/coach/admin role) for the sibling migration.
///
/// `.other(String)` is the fallback for any stored value that isn't exactly
/// one of the three known roles — retains the ORIGINAL string exactly, so
/// `normalize` never silently drops or coerces unrecognized data (real
/// roster imports, per cerebrum.md's 2026-07-30 entry, are not always
/// perfectly formatted). `.other` is deliberately treated as "not a helper"
/// (not coach/assistant) everywhere the app branches on that distinction —
/// same fail-safe default the removed `!isHelfer` bug already should have
/// had.
enum MembershipRole: RawRepresentable, Hashable {
    case player
    case coach
    case assistant
    case other(String)

    private static let knownCases: [String: MembershipRole] = [
        "player": .player,
        "coach": .coach,
        "assistant": .assistant,
    ]

    init?(rawValue: String) {
        self = MembershipRole.normalize(rawValue)
    }

    var rawValue: String {
        switch self {
        case .player: return "player"
        case .coach: return "coach"
        case .assistant: return "assistant"
        case .other(let raw): return raw
        }
    }

    /// Maps any stored/wire string to a defined case — always succeeds,
    /// never crashes. Unknown values land in `.other(raw)`, preserving the
    /// original text.
    static func normalize(_ raw: String) -> MembershipRole {
        knownCases[raw] ?? .other(raw)
    }

    /// True for "Helfer" (coach or assistant) — matches this app's existing
    /// `isHelfer`/PRAE-eligibility vocabulary (Models.swift's `Attendance.praeAmount`
    /// doc comment, TournamentsViews/TrainingsViews' Anwesenheit sections).
    /// `.other` is never a helper — an unrecognized role must never be
    /// treated as PRAE-eligible or excluded from the Sportler roster by
    /// accident.
    var isHelfer: Bool {
        switch self {
        case .coach, .assistant: return true
        case .player, .other: return false
        }
    }

    /// German display label, matching TeamsViews.swift's existing Picker/
    /// accessibility label vocabulary — `.other` shows its raw value
    /// verbatim rather than a generic placeholder.
    var displayLabel: String {
        switch self {
        case .player: return "Spieler:in"
        case .coach: return "Trainer:in"
        case .assistant: return "Assistent:in"
        case .other(let raw): return raw
        }
    }
}

extension MembershipRole: Codable {
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = MembershipRole.normalize(raw)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
