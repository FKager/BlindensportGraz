import SwiftUI
import SwiftData

/// "Für alle Mitglieder anzeigen" switch for the shared welcome screen.
/// Bound to local `@State`: only the admin flipping it saves and pushes
/// `WelcomeContent`; a value pulled from CloudKit just updates the switch.
struct WelcomeEnabledToggle: View {
    let content: WelcomeContent

    @Environment(\.modelContext) private var modelContext
    @State private var isEnabled = false

    var body: some View {
        Toggle("Für alle Mitglieder anzeigen", isOn: $isEnabled)
            .onChange(of: content.isEnabled, initial: true) { _, stored in
                isEnabled = stored
            }
            .onChange(of: isEnabled) { _, enabled in
                guard enabled != content.isEnabled else { return }
                content.isEnabled = enabled
                WelcomeContentService.save(content, modelContext: modelContext)
            }
    }
}
