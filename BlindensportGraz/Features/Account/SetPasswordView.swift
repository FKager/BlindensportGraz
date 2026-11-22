import SwiftUI

/// Sets a new password for the signed-in Supabase account — after opening a
/// password-reset link (`AuthContext.isPasswordRecovery`), or from the
/// Account tab (e.g. an account that so far only used Sign in with Apple).
/// If the account hasn't signed in for a while, the server asks to confirm
/// the change: a code is mailed and asked for here (`PasswordChangeStep`).
struct SetPasswordView: View {
    var title: LocalizedStringKey = "Passwort festlegen"
    let onComplete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var passwordConfirm = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    /// Set once the server asked to confirm the change by email code.
    @State private var askingForCode = false
    @State private var code = ""
    @State private var isSendingCode = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Neues Passwort", text: $password)
                        .textContentType(.newPassword)
                    SecureField("Passwort wiederholen", text: $passwordConfirm)
                        .textContentType(.newPassword)
                    if !password.isEmpty, !Validation.passwordMeetsMinimumStrength(password) {
                        Label("Mindestens 10 Zeichen, mit Buchstaben und Ziffern", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(Theme.Palette.warning)
                    }
                    if !passwordConfirm.isEmpty, password != passwordConfirm {
                        Label("Passwörter stimmen nicht überein", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(Theme.Palette.warning)
                    }
                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(Theme.Palette.warning)
                    }
                }
                if askingForCode {
                    Section {
                        TextField("Bestätigungscode", text: $code)
                            .textContentType(.oneTimeCode)
                            .keyboardType(.numberPad)
                        Button(isSendingCode ? "Code wird gesendet …" : "Neuen Code senden") {
                            Task { await sendCode() }
                        }
                        .disabled(isSendingCode)
                    } header: {
                        SectionHeading("Bestätigung")
                    } footer: {
                        Text("Zur Sicherheit haben wir dir einen Code per E-Mail geschickt. Gib ihn hier ein und tippe auf Speichern.")
                            .foregroundStyle(Theme.Palette.secondary)
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") {
                        dismiss()
                        onComplete()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") { Task { await save() } }
                        .disabled(isSaving || !Validation.passwordMeetsMinimumStrength(password)
                                  || password != passwordConfirm
                                  || (askingForCode && PasswordChangeStep.cleanedCode(code).count < 6))
                }
            }
        }
    }

    private func save() async {
        errorMessage = nil
        isSaving = true
        defer { isSaving = false }
        do {
            let nonce = askingForCode ? PasswordChangeStep.cleanedCode(code) : nil
            try await SupabaseAuthService.updatePassword(password, nonce: nonce)
            dismiss()
            onComplete()
        } catch {
            switch PasswordChangeStep.after(error) {
            case .askForCode:
                await sendCode()
            case .codeRejected, .failed:
                show(AuthErrorMessage.text(for: error))
            }
        }
    }

    private func sendCode() async {
        isSendingCode = true
        defer { isSendingCode = false }
        do {
            try await SupabaseAuthService.sendReauthenticationCode()
            askingForCode = true
            code = ""
            errorMessage = nil
            AccessibilityNotification.Announcement(
                String(localized: "Bestätigungscode per E-Mail gesendet. Bitte gib ihn ein.")).post()
        } catch {
            show(AuthErrorMessage.text(for: error))
        }
    }

    /// Shown under the fields and read out, as it appears away from the VoiceOver cursor.
    private func show(_ message: String) {
        errorMessage = message
        AccessibilityNotification.Announcement(message).post()
    }
}
