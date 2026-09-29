import Foundation

/// Closed enum for `User.role` (app-level account role: member/coach/admin) —
/// audit.md Architecture Finding 3, alongside `MembershipRole`
/// (`TeamMembership.role`, see TeamMembership.swift). Replaces a bare
/// `String` field that admin-gating code across the app compared against
/// string literals (`user.role` compared to `"admin"`, 20+ call sites) with no
/// compile-time protection against a typo.
///
/// `.other(String)` is the fallback for any stored value that isn't exactly
/// one of the three known roles (a future role, corrupted/legacy data, a
/// hand-edited CloudKit record) — it retains the ORIGINAL string exactly,
/// so `normalize` never silently drops or coerces unrecognized data
/// (per audit.md's own "never crash or silently drop data" requirement for
/// this migration). `.other` is deliberately treated as non-admin/non-coach
/// everywhere access is gated — an unrecognized role must never be
/// interpreted as elevated access.
enum AppRole: RawRepresentable, Hashable {
    case member
    case coach
    case admin
    case other(String)

    private static let knownCases: [String: AppRole] = [
        "member": .member,
        "coach": .coach,
        "admin": .admin,
    ]

    init?(rawValue: String) {
        self = AppRole.normalize(rawValue)
    }

    var rawValue: String {
        switch self {
        case .member: return "member"
        case .coach: return "coach"
        case .admin: return "admin"
        case .other(let raw): return raw
        }
    }

    /// Maps any stored/wire string to a defined case — always succeeds,
    /// never crashes. Unknown values land in `.other(raw)`, preserving the
    /// original text.
    static func normalize(_ raw: String) -> AppRole {
        knownCases[raw] ?? .other(raw)
    }

    /// German display label, matching this app's existing UI vocabulary
    /// (RootView/AccountView's Picker labels) — `.other` shows its raw
    /// value verbatim rather than a generic "unknown" placeholder, so an
    /// admin looking at a garbled record can still see what was actually
    /// stored.
    var displayLabel: String {
        switch self {
        case .member: return "Mitglied"
        case .coach: return "Trainer:in"
        case .admin: return "Admin"
        case .other(let raw): return raw
        }
    }
}

extension AppRole: Codable {
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = AppRole.normalize(raw)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
