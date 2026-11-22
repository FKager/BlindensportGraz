import SwiftUI

/// A sheet's title as a heading at the top of its form. Unlike the inline
/// navigation bar title it wraps at large text sizes instead of being cut
/// off, and VoiceOver reaches it first (heading trait).
struct FormTitleHeader: View {
    let title: LocalizedStringKey

    var body: some View {
        Section {
            Text(title)
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: Theme.Spacing.s, leading: 0, bottom: 0, trailing: 0))
        }
    }
}
