import SwiftUI
import SwiftData
import AuthenticationServices

/// One-time migration step for an account created before password login
/// existed (passwordHash empty) — see LoginView.attemptLogin's doc comment
/// for the trust-model caveat this implies.
struct SetPasswordView: View {
    let user: User
    let onComplete: (User) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var passwordConfirm = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Für \(user.displayName) wurde noch kein Passwort festgelegt. Bitte jetzt eines vergeben.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Passwort festlegen")
                }
                Section {
                    SecureField("Passwort", text: $password)
                    SecureField("Passwort wiederholen", text: $passwordConfirm)
                    if !password.isEmpty, !Validation.passwordMeetsMinimumStrength(password) {
                        Label("Passwort muss mindestens 8 Zeichen haben", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(Theme.Palette.warning)
                    }
                    if !passwordConfirm.isEmpty, password != passwordConfirm {
                        Label("Passwörter stimmen nicht überein", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(Theme.Palette.warning)
                    }
                }
            }
            .navigationTitle("Passwort festlegen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") {
                        let salt = PasswordHashing.makeSalt()
                        user.passwordSalt = salt
                        user.passwordHash = PasswordHashing.hash(password: password, salt: salt)
                        UserService.save(user, modelContext: modelContext)
                        dismiss()
                        onComplete(user)
                    }
                    .disabled(!Validation.passwordMeetsMinimumStrength(password) || password != passwordConfirm)
                }
            }
        }
    }
}
