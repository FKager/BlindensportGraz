import SwiftUI

/// Sets a new password for the signed-in Supabase account — after opening a
/// password-reset link (`AuthContext.isPasswordRecovery`), or from the
/// Account tab (e.g. an account that so far only used Sign in with Apple).
struct SetPasswordView: View {
    var title: LocalizedStringKey = "Passwort festlegen"
    let onComplete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var passwordConfirm = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

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
                                  || password != passwordConfirm)
                }
            }
        }
    }

    private func save() async {
        errorMessage = nil
        isSaving = true
        defer { isSaving = false }
        do {
            try await SupabaseAuthService.updatePassword(password)
            dismiss()
            onComplete()
        } catch {
            errorMessage = AuthErrorMessage.text(for: error)
        }
    }
}
