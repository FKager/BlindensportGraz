import SwiftUI

/// A sheet's actions as large buttons inside the form: the main action and
/// cancel / done. Large buttons scale with Dynamic Type (navigation bar
/// buttons don't), and they're never greyed out: the main action says
/// what's missing instead (see the `onPrimary` of each form).
struct FormActionButtons: View {
    let primaryTitle: LocalizedStringKey?
    /// nil: no second button (e.g. edit screens, whose edits apply live).
    let cancelTitle: LocalizedStringKey?
    var isWorking = false
    /// What's missing or went wrong, shown above the buttons.
    var message: String?
    var onPrimary: () -> Void = {}
    var onCancel: () -> Void = {}

    var body: some View {
        Section {
            if let message {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(Theme.Palette.warning)
                    .listRowBackground(Color.clear)
            }
            if let primaryTitle {
                Button(action: onPrimary) {
                    HStack {
                        Text(primaryTitle)
                        if isWorking {
                            ProgressView()
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.Fill.info)
                .listRowBackground(Color.clear)
            }
            if let cancelTitle {
                Button(action: onCancel) {
                    Text(cancelTitle)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                // Primary text colour: the default accent text on the grey button misses the contrast ratio.
                .tint(.primary)
                .listRowBackground(Color.clear)
            }
        }
        .listRowSeparator(.hidden)
    }
}
