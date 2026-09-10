import SwiftUI

/// First slice of a shared design system (architecture-review.md §3.1) —
/// introduced here rather than as a big-bang sweep, adopted by whatever view
/// is being touched anyway. Colours are semantic and system-derived so they
/// adapt to light/dark automatically (architecture-review.md §5 dark-mode
/// item) instead of the ad-hoc `Color.blue.opacity(0.1)` fills scattered
/// through the views.
enum Theme {
    /// Standard corner radius for cards / tappable tiles.
    static let cornerRadius: CGFloat = 12

    /// Fill behind a card. `.quaternary` tracks the system fill hierarchy in
    /// both colour schemes — legible in dark mode, unlike a fixed
    /// `someColor.opacity(0.1)`.
    static let cardFill: AnyShapeStyle = AnyShapeStyle(.quaternary)

    /// A tinted card fill, e.g. the coloured stat tiles — 12% of an accent
    /// colour over the system background, so it stays subtle in dark mode too.
    static func tintedCardFill(_ color: Color) -> some ShapeStyle {
        color.opacity(0.12)
    }

    /// Fill fraction for a small tinted badge/pill/icon-circle — the "Text +
    /// padding + faint capsule behind it" status/role/tag pattern repeated
    /// (with drifting magic numbers: 0.12/0.15/0.2) across TeamsViews,
    /// AccountView, MembersViews, TournamentsViews and SportIcons
    /// (architecture-review.md §3.1/§5 dark-mode pass). Subtle in both colour
    /// schemes because it blends with a dynamic system base colour (`.blue`,
    /// `.orange`, a role/status colour) — those already shift brightness for
    /// dark mode, this just keeps the tint fraction consistent everywhere
    /// instead of each call site picking its own.
    static let badgeOpacity: Double = 0.15
    /// Slightly stronger tint for a badge meant to stand out more (a status
    /// pill, the "ROOT" indicator) rather than a plain tag.
    static let emphasizedBadgeOpacity: Double = 0.2
}

private struct CardModifier: ViewModifier {
    var tint: Color?

    func body(content: Content) -> some View {
        content
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerRadius)
                    .fill(tint.map { AnyShapeStyle(Theme.tintedCardFill($0)) } ?? Theme.cardFill)
            )
    }
}

extension View {
    /// Wraps the view in the app's standard card: inset padding, full width,
    /// rounded system-derived fill (optionally tinted).
    func card(tint: Color? = nil) -> some View {
        modifier(CardModifier(tint: tint))
    }

    /// Small tinted pill background for a status/role/tag label — apply
    /// after the label's own padding. Callers keep their own font/foreground.
    func badge(tint: Color, opacity: Double = Theme.badgeOpacity) -> some View {
        background(tint.opacity(opacity), in: Capsule())
    }
}
