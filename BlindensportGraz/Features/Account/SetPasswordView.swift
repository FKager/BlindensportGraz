import SwiftUI
import SwiftData
import AuthenticationServices

/// Sets the first password for an account created before password login
/// existed (passwordHash empty).
///
/// Coming from the login screen (`requiresActivationCode`), the person must
/// first enter a one-time activation code an admin created for this account
/// (`AccountApproval`, "App-Konten") — otherwise anyone who knows the email
/// could claim the account by being first to set a password. From the
/// Account tab the person is already signed in (e.g. via Apple on their own
/// iPhone), so no code is needed.
struct SetPasswordView: View {
    let user: User
    let requiresActivationCode: Bool
    let onComplete: (User) -> Void

    @Query private var approvals: [AccountApproval]
    @Query private var users: [User]
    @State private var activationCode = ""
    @State private var codeRejected = false

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
                if requiresActivationCode {
                    Section {
                        TextField("Aktivierungscode", text: $activationCode)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                        if codeRejected {
                            Label("Der Aktivierungscode stimmt nicht.", systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundStyle(Theme.Palette.warning)
                        }
                    } header: {
                        Text("Aktivierungscode")
                    } footer: {
                        Text("Den Code bekommst du von einem Admin (Verein → App-Konten). Er schützt dein Konto davor, dass jemand anderer mit deiner E-Mail-Adresse ein Passwort festlegt.")
                    }
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
                        if requiresActivationCode,
                           !ActivationCode.matches(activationCode, for: user, approvals: approvals, users: users) {
                            codeRejected = true
                            return
                        }
                        let salt = PasswordHashing.makeSalt()
                        user.passwordSalt = salt
                        user.passwordHash = PasswordHashing.hash(password: password, salt: salt)
                        UserService.save(user, modelContext: modelContext)
                        dismiss()
                        onComplete(user)
                    }
                    .disabled(!Validation.passwordMeetsMinimumStrength(password) || password != passwordConfirm
                              || (requiresActivationCode && ActivationCode.normalized(activationCode).count != 8))
                }
            }
        }
    }
}
