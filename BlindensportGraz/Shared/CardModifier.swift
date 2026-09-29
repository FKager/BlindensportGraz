import SwiftUI

/// The app's standard card: inset padding, full width, rounded
/// system-derived fill (optionally tinted). Applied via `.card(tint:)`.
struct CardModifier: ViewModifier {
    var tint: Color?

    func body(content: Content) -> some View {
        content
            .padding(Theme.Spacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.card)
                    .fill(tint.map { AnyShapeStyle(Theme.tintedCardFill($0)) } ?? Theme.cardFill)
            )
    }
}

extension View {
    /// Wraps the view in the app's standard card.
    func card(tint: Color? = nil) -> some View {
        modifier(CardModifier(tint: tint))
    }

    /// Small tinted pill background — prefer `TagLabel`, which also sets the
    /// font, padding and text colour.
    func badge(tint: Color, opacity: Double = Theme.badgeOpacity) -> some View {
        background(tint.opacity(opacity), in: .capsule)
    }
}
