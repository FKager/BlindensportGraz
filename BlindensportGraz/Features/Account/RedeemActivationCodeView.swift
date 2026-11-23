import SwiftUI

/// A pending account enters the one-time code an admin created for it
/// (App-Konten → Aktivierungscode). The server checks the code belongs to
/// this account; if the admin linked a roster entry, the account is approved
/// and a token refresh unlocks the full app.
struct RedeemActivationCodeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthContext.self) private var authContext
    @State private var code = ""
    @State private var isWorking = false
    @State private var errorMessage: String?

    /// What's missing; shown above the buttons and read out.
    @State private var formMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                FormTitleHeader(title: "Aktivierungscode")
                Section {
                    StackedField(label: "Aktivierungscode", text: $code)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .textContentType(.oneTimeCode)
                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(Theme.Palette.warning)
                    }
                } footer: {
                    Text("Den Code bekommst du von einem Admin. Er gilt 14 Tage und nur für dein Konto.")
                        .foregroundStyle(Theme.Palette.secondary)
                }
                FormActionButtons(primaryTitle: "Einlösen", cancelTitle: "Abbrechen", isWorking: isWorking, message: formMessage,
                                  onPrimary: attemptSave, onCancel: { dismiss() })
            }
        }
    }

    private func redeem() async {
        errorMessage = nil
        isWorking = true
        defer { isWorking = false }
        do {
            if try await SupabaseApprovalService.redeemActivationCode(code) {
                await authContext.refresh()
                dismiss()
            } else {
                errorMessage = String(localized: "Der Code ist ungültig, abgelaufen oder schon verwendet.")
            }
        } catch {
            errorMessage = AuthErrorMessage.text(for: error)
        }
    }

    /// "Einlösen" is never greyed out: it says what's missing instead.
    private func attemptSave() {
        guard !isWorking else { return }
        if ActivationCode.normalized(code).count != 8 {
            show(String(localized: "Der Code hat 8 Zeichen."))
            return
        }
        formMessage = nil
        performPrimary()
    }

    private func performPrimary() {
        Task { await redeem() }
    }

    /// Shown above the buttons and read out, as it appears away from the VoiceOver cursor.
    private func show(_ message: String) {
        formMessage = message
        AccessibilityNotification.Announcement(message).post()
    }
}
