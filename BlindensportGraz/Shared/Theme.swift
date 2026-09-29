import SwiftUI

/// The app's design tokens — the one place to tune spacing, rounding and
/// colour (architecture-review.md §3.1/§5). Views use these instead of raw
/// numbers and `.orange`/`.green` literals; shared building blocks live next
/// to this file (`.card()`, `TagLabel`, `CountBadge`, `HeroIcon`).
enum Theme {
    /// Spacing scale for stack spacing and padding.
    enum Spacing {
        static let xxs: Double = 2
        static let xs: Double = 4
        static let s: Double = 8
        static let m: Double = 12
        static let l: Double = 16
        static let xl: Double = 20
        static let xxl: Double = 24
        /// Space above a screen's hero header.
        static let hero: Double = 32
    }

    /// Corner radii (continuous corners — RoundedRectangle's default).
    enum Radius {
        /// Thumbnails, date badges.
        static let small: Double = 8
        /// Cards, tiles, featured images.
        static let card: Double = 12
    }

    /// Semantic colours for text and symbols that carry meaning. Asset-catalog
    /// colours with light, dark and Increase Contrast variants, each at least
    /// 4.5:1 (WCAG AA) against the system backgrounds — the raw system
    /// `.orange`/`.green` only reach about 2.2:1 on white, which is too faint
    /// for this app's low-vision users.
    enum Palette {
        /// Positive state: present, approved, member, held.
        static let success = Color(.successText)
        /// Validation hints and "needs attention" notes.
        static let warning = Color(.warningText)
        /// Errors, cancellations, limits exceeded, negative balances.
        static let danger = Color(.dangerText)
        /// Informational icons and neutral-positive tags (e.g. "planned").
        static let info = Color(.infoText)
    }

    /// Accent per app area — icons on tinted tiles (Dashboard stat tiles,
    /// "Nächster Termin" card, event date badge), always next to a text
    /// label (never the only carrier of meaning). Asset-catalog colours with
    /// dark and Increase Contrast variants: each icon reaches at least 4.5:1
    /// against its own 12–15% tinted tile, in every mode. The system colours
    /// they replace were far below that (yellow trophy 1.4:1, green 2.0:1).
    /// Tournaments reads as dark gold in light mode — a bright yellow can't
    /// reach readable contrast on white.
    enum Accent {
        static let events = Color(.eventsAccent)
        static let tournaments = Color(.tournamentsAccent)
        static let trainings = Color(.trainingsAccent)
        static let teams = Color(.teamsAccent)
    }

    /// Brand gradient for avatars and hero icons.
    static let brandGradient = LinearGradient(colors: [.blue, .purple],
                                              startPoint: .topLeading, endPoint: .bottomTrailing)

    /// Fill behind an untinted card. `.quaternary` follows the system fill
    /// hierarchy in both colour schemes.
    static let cardFill: AnyShapeStyle = AnyShapeStyle(.quaternary)

    /// Tinted card fill — 12% of an accent over the system background, so it
    /// stays subtle in dark mode too.
    static func tintedCardFill(_ color: Color) -> some ShapeStyle {
        color.opacity(0.12)
    }

    /// Tint fraction behind a `TagLabel`/badge.
    static let badgeOpacity: Double = 0.15
    /// Stronger tint for a badge that should stand out (a status, "ROOT").
    static let emphasizedBadgeOpacity: Double = 0.2
}
