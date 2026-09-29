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
                VStack(alignment: .leading, spacing: 16) {
                    Image(systemName: "hand.wave.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(
                            LinearGradient(colors: [.blue, .purple],
                                           startPoint: .topLeading, endPoint: .bottomTrailing))
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
