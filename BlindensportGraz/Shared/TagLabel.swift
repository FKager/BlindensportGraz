import SwiftUI

/// Small pill label for a status, role or tag ("geplant", "Trainer:in",
/// "ROOT"). One definition instead of each row picking its own font,
/// padding and tint strength. Uses `.caption` — never `.caption2`, which is
/// too small for this app's users — and scales with Dynamic Type.
struct TagLabel: View {
    private let text: Text
    private let tint: Color
    private let emphasized: Bool

    /// Localized label (string literals, `LocalizedStringKey`s) — like `Text("…")`.
    /// - Parameter emphasized: Stronger fill and bold text, for a status that
    ///   should stand out.
    init(_ key: LocalizedStringKey, tint: Color = Theme.Palette.info, emphasized: Bool = false) {
        self.text = Text(key)
        self.tint = tint
        self.emphasized = emphasized
    }

    /// Verbatim label for model values (a stored status or role) — like `Text(someString)`.
    init<S: StringProtocol>(_ string: S, tint: Color = Theme.Palette.info, emphasized: Bool = false) {
        self.text = Text(string)
        self.tint = tint
        self.emphasized = emphasized
    }

    var body: some View {
        text
            .font(emphasized ? .caption.bold() : .caption)
            .foregroundStyle(tint)
            .padding(.horizontal, Theme.Spacing.s)
            .padding(.vertical, Theme.Spacing.xxs)
            .badge(tint: tint, opacity: emphasized ? Theme.emphasizedBadgeOpacity : Theme.badgeOpacity)
    }
}
