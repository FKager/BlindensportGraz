import SwiftUI
import SwiftData

struct NextUpCard: View {
    let icon: String
    let kind: LocalizedStringKey
    let title: String
    let subtitle: String
    let tint: Color

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(kind)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.footnote.bold())
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .card(tint: tint)
        .accessibilityElement(children: .combine)
    }
}
