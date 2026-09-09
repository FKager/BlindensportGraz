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
}
