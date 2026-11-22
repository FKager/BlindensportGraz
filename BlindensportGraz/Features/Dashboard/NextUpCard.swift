import SwiftUI
import SwiftData

struct NextUpCard: View {
    let icon: String
    let kind: LocalizedStringKey
    let title: String
    let subtitle: String
    let tint: Color

    /// From xxLarge text the decorative icon gives its width to the title,
    /// so long names like "Blindenfußballtraining" aren't cut off.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(spacing: Theme.Spacing.l) {
            if dynamicTypeSize < .xxLarge {
                Image(systemName: icon)
                    .font(.title)
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(kind)
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.secondary)
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(Theme.Palette.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.footnote.bold())
                .foregroundStyle(Theme.Palette.secondary)
                .accessibilityHidden(true)
        }
        .card(tint: tint)
        .accessibilityElement(children: .combine)
    }
}
