import SwiftUI
import SwiftData

/// Full-screen welcome note shown by `RootView` on launch (when enabled and
/// non-empty) and reused by `WelcomeScreenSettingsView`'s preview.
struct WelcomeView: View {
    let markdown: String
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    HeroIcon(systemName: "hand.wave.fill", size: 44)
                        .frame(maxWidth: .infinity)

                    MarkdownContentView(markdown: markdown)
                }
                .padding()
            }
            .navigationTitle("Willkommen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Weiter") { onDismiss() }
                }
            }
        }
    }
}
