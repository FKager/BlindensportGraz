import Foundation

/// Closed enum for `BudgetEntry.category` — mirrors `AppRole`/`MembershipRole`
/// exactly (a fixed, app-defined set with a `.other(String)` fallback for
/// corrupted/legacy/future data), NOT `Sport`'s free-text pattern, since
/// budget categories aren't something a club admin invents on the fly the
/// way a sport name is.
///
/// `.other` retains the original string exactly, same "never silently drop
/// or coerce unrecognized data" rule `AppRole.normalize` documents.
enum BudgetCategory: RawRepresentable, Hashable {
    /// Fixed annual subsidy (e.g. city/state funding) — the amount varies
    /// year to year, but it's still just a regular ledger entry, not a
    /// special single-value-per-year field (user confirmed one entry per
    /// year is the typical/expected shape, nothing enforces exactly one).
    case fixedSubsidy
    case donation
    /// Event/training/tournament costs NOT already covered by
    /// `Attendance.praeAmount` (venue rental, referee fees, registration
    /// fees, ...) — see `BudgetSummary.swift` for how this combines with the
    /// existing PRAE total into one honest event-cost figure.
    case eventCost
    /// General expenses, e.g. buying training materials.
    case otherExpense
    case other(String)

    private static let knownCases: [String: BudgetCategory] = [
        "fixedSubsidy": .fixedSubsidy,
        "donation": .donation,
        "eventCost": .eventCost,
        "otherExpense": .otherExpense,
    ]

    init?(rawValue: String) {
        self = BudgetCategory.normalize(rawValue)
    }

    var rawValue: String {
        switch self {
        case .fixedSubsidy: return "fixedSubsidy"
        case .donation: return "donation"
        case .eventCost: return "eventCost"
        case .otherExpense: return "otherExpense"
        case .other(let raw): return raw
        }
    }

    /// Maps any stored/wire string to a defined case — always succeeds,
    /// never crashes. Unknown values land in `.other(raw)`, preserving the
    /// original text (same convention as `AppRole.normalize`).
    static func normalize(_ raw: String) -> BudgetCategory {
        knownCases[raw] ?? .other(raw)
    }

    /// Drives income-vs-expense entirely — there's no separate stored `kind`
    /// field, so a category and its income/expense side can never disagree.
    /// `.other` is fail-safe treated as an EXPENSE, matching
    /// `MembershipRole.isHelfer`'s "unrecognized == not the privileged side"
    /// precedent — a corrupted/unrecognized category must never inflate the
    /// club's reported income.
    var isIncome: Bool {
        switch self {
        case .fixedSubsidy, .donation: return true
        case .eventCost, .otherExpense, .other: return false
        }
    }

    /// German display label, matching this app's existing UI vocabulary.
    /// `.other` shows its raw value verbatim rather than a generic "unknown"
    /// placeholder, so an admin looking at a garbled record can still see
    /// what was actually stored.
    var displayLabel: String {
        switch self {
        case .fixedSubsidy: return "Fixer Zuschuss"
        case .donation: return "Spende"
        case .eventCost: return "Veranstaltungskosten"
        case .otherExpense: return "Sonstige Ausgabe"
        case .other(let raw): return raw
        }
    }
}

extension BudgetCategory: Codable {
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = BudgetCategory.normalize(raw)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
