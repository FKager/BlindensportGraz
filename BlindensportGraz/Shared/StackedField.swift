import SwiftUI

/// A text or password field with its label above it instead of a
/// placeholder inside it (the field itself stays empty, no repeated name): long labels wrap at large text sizes instead of
/// being cut off, and the label stays visible while typing. VoiceOver reads
/// the label once, as the field's own label.
struct StackedField: View {
    let label: LocalizedStringKey
    @Binding var text: String
    var secure = false
    /// `.vertical` for a multi-line field (notes, descriptions).
    var axis: Axis = .horizontal

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(label)
                .font(.subheadline)
                // Full text colour: the grey .secondary misses 4.5:1 in light mode.
                .foregroundStyle(Color.primary)
                .accessibilityHidden(true)
            Group {
                if secure {
                    SecureField(text: $text, prompt: Text(verbatim: "")) { Text(label) }
                } else {
                    TextField(text: $text, prompt: Text(verbatim: ""), axis: axis) { Text(label) }
                }
            }
            .accessibilityLabel(Text(label))
        }
        .padding(.vertical, Theme.Spacing.xs)
    }
}
