import Foundation

/// Closed enum for the app's known sports — audit.md Architecture Finding 3
/// groups this alongside `TeamMembership.role`'s confirmed bug as "also
/// free-text, same class of risk." Unlike `role`, though, `sport` is a
/// DELIBERATE design decision to stay free text on the model (see
/// `SportIcon.swift`'s own doc comment: "not a fixed enum" — every
/// Team/SportEvent/Training/Tournament/TrainingFavorite `sport: String`
/// field is edited via a plain `TextField`, not just a `Picker`, precisely
/// so a club admin can type a sport this app doesn't know about yet without
/// being blocked). Grepping the entire app for equality/inequality
/// comparisons against `sport` (this phase's own acceptance check) returns
/// zero hits — there's no existing typo-prone comparison bug to fix here,
/// unlike `role`.
///
/// So `Sport` is provided as a NORMALIZATION UTILITY, not a stored model
/// property type — `sport` stays `String` everywhere on the models
/// (preserving free-text editing exactly as before), and this enum exists
/// for anywhere the app wants type-safe switching over the *known* sports
/// with a graceful, data-preserving fallback for anything else. See
/// `SportIcon.swift`, refactored in this same phase to use this shared
/// enum instead of its own private, duplicated normalize+switch logic.
enum Sport: RawRepresentable, Hashable {
    case torball
    case goalball
    case blindenfussball
    case showdown
    case judo
    case leichtathletik
    case schwimmen
    case ski
    case radfahren
    case other(String)

    /// Canonical display strings, matching what `Team.defaultTeams`/
    /// `Team.autoAssignTeamNames`/every "Sportart" Picker in the app already
    /// writes — these are the RAW VALUES, used for both display and as the
    /// dictionary/CloudKit wire strings, unchanged by this phase.
    private static let knownCases: [String: Sport] = [
        "torball": .torball,
        "goalball": .goalball,
        "blindenfußball": .blindenfussball,
        "showdown": .showdown,
        "judo": .judo,
        "leichtathletik": .leichtathletik,
        "schwimmen": .schwimmen,
        "ski": .ski,
        "radfahren": .radfahren,
    ]

    init?(rawValue: String) {
        self = Sport.normalize(rawValue)
    }

    var rawValue: String {
        switch self {
        case .torball: return "Torball"
        case .goalball: return "Goalball"
        case .blindenfussball: return "Blindenfußball"
        case .showdown: return "Showdown"
        case .judo: return "Judo"
        case .leichtathletik: return "Leichtathletik"
        case .schwimmen: return "Schwimmen"
        case .ski: return "Ski"
        case .radfahren: return "Radfahren"
        case .other(let raw): return raw
        }
    }

    /// Same normalization SportIcon.swift already did privately (trim,
    /// lowercase, fold ß/ü) — matches on the FOLDED form so "Blindenfußball"/
    /// "blindenfussball"/" Blindenfußball " all resolve to `.blindenfussball`,
    /// but always returns the canonical German spelling via `rawValue`.
    /// Anything not recognized falls back to `.other(raw)` — the exact
    /// original text, untouched, never dropped or coerced.
    static func normalize(_ raw: String) -> Sport {
        let folded = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "ß", with: "ss")
            .replacingOccurrences(of: "ü", with: "u")
        // knownCases keys are already stored ß/ü-native; fold them the same
        // way at lookup time so "fussball"/"fußball" both match.
        let foldedKeys = Dictionary(uniqueKeysWithValues: knownCases.map { key, value in
            (key.replacingOccurrences(of: "ß", with: "ss").replacingOccurrences(of: "ü", with: "u"), value)
        })
        return foldedKeys[folded] ?? .other(raw)
    }
}
