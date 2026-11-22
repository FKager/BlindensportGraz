import SwiftUI

/// "Passwort vergessen": Supabase emails a link that opens the app
/// (blindensportgraz://auth-callback); `AuthContext` then sets
/// `isPasswordRecovery` and `RootView` asks for the new password.
struct ResetPasswordRequestView: View {
    @Environment(\.dismiss) private var dismiss
    @State var email: String
    @State private var sent = false
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                FormTitleHeader(title: "Passwort vergessen")
                Section {
                    Text("Wir schicken dir einen Link. Öffne ihn auf diesem iPhone, um ein neues Passwort festzulegen.")
                    StackedField(label: "E-Mail", text: $email)
                        .keyboardType(.emailAddress)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if sent {
                        Label("E-Mail ist unterwegs. Bitte schau in dein Postfach.", systemImage: "envelope.badge")
                    }
                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .font(.callout)
                            .foregroundStyle(Theme.Palette.warning)
                    }
                }
                FormActionButtons(primaryTitle: sent ? nil : "Link senden", cancelTitle: sent ? "Fertig" : "Abbrechen",
                                  isWorking: isWorking, onPrimary: submit, onCancel: { dismiss() })
            }
        }
    }

    private func submit() {
        guard !isWorking else { return }
        guard Validation.isPlausibleEmail(email) else {
            show(String(localized: "Bitte gib eine gültige E-Mail-Adresse ein."))
            return
        }
        Task { await send() }
    }

    /// Shown in the form and read out, as it appears away from the VoiceOver cursor.
    private func show(_ message: String) {
        errorMessage = message
        AccessibilityNotification.Announcement(message).post()
    }

    private func send() async {
        errorMessage = nil
        isWorking = true
        defer { isWorking = false }
        do {
            try await SupabaseAuthService.resetPassword(
                email: email.trimmingCharacters(in: .whitespaces).lowercased())
            sent = true
            AccessibilityNotification.Announcement(String(localized: "E-Mail ist unterwegs. Bitte schau in dein Postfach.")).post()
        } catch {
            show(AuthErrorMessage.text(for: error))
        }
    }
}
