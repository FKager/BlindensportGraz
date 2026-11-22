import SwiftUI

/// "Nothing here" message for an empty list or screen, used instead of
/// ContentUnavailableView: that one cuts its title off at large text sizes
/// and draws the description in a grey under 4.5:1 in light mode (found by
/// the accessibility audit, BlindensportGrazUITests). Title is a heading
/// for VoiceOver; the icon is decorative.
struct EmptyStateView: View {
    let title: LocalizedStringKey
    let systemImage: String
    var description: LocalizedStringKey?

    init(_ title: LocalizedStringKey, systemImage: String, description: LocalizedStringKey? = nil) {
        self.title = title
        self.systemImage = systemImage
        self.description = description
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.s) {
            Image(systemName: systemImage)
                .font(.largeTitle)
                .accessibilityHidden(true)
            Text(title)
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
            if let description {
                Text(description)
            }
        }
        .foregroundStyle(Color.primary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, Theme.Spacing.xxl)
        .listRowBackground(Color.clear)
    }
}
