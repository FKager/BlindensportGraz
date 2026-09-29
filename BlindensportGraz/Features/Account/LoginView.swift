import SwiftUI
import SwiftData
import AuthenticationServices

struct LoginView: View {
    let onLogin: (User) -> Void
    let onAppleSignIn: () async -> Void

    // Unfiltered — looked up by email below rather than browsed/tapped, so
    // there's no picker to hide the designated-root account from anymore
    // (that was `visibleUsers`' whole job in the old tap-a-name list —
    // removed along with the list itself, see this struct's history).
    @Query private var users: [User]

    @State private var email = ""
    @State private var password = ""
    @State private var errorMessage: String?
    @State private var showRegister = false
    // Set when the matched account predates password login (passwordHash
    // still empty) — routes to SetPasswordView instead of rejecting.
    @State private var userNeedingPassword: User?

    var body: some View {
        NavigationStack {
            Form {
                Section("Anmelden") {
                    TextField("E-Mail", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Passwort", text: $password)
                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(Theme.Palette.warning)
                    }
                    Button("Anmelden") { attemptLogin() }
                        .disabled(email.trimmingCharacters(in: .whitespaces).isEmpty || password.isEmpty)
                }
                Section {
                    Button("Mit Apple anmelden") { Task { await onAppleSignIn() } }
                }
                Section {
                    Button("Neues Konto erstellen") { showRegister = true }
                }
            }
            .navigationTitle("Anmelden")
            .sheet(isPresented: $showRegister) {
                RegisterView(onRegister: onLogin)
            }
            .sheet(item: $userNeedingPassword) { user in
                SetPasswordView(user: user, requiresActivationCode: true, onComplete: onLogin)
            }
        }
    }

    private func attemptLogin() {
        errorMessage = nil
        let needle = email.trimmingCharacters(in: .whitespaces).lowercased()
        guard let match = users.first(where: { $0.email.lowercased() == needle }) else {
            errorMessage = "Kein Konto mit dieser E-Mail-Adresse gefunden."
            return
        }
        // Account from before password login (passwordHash empty): setting
        // its first password needs a one-time activation code from an admin
        // (SetPasswordView) — knowing the email alone must not be enough to
        // claim someone else's account.
        guard !match.passwordHash.isEmpty else {
            userNeedingPassword = match
            return
        }
        guard PasswordHashing.verify(password: password, salt: match.passwordSalt, expectedHash: match.passwordHash) else {
            errorMessage = "Falsches Passwort."
            return
        }
        onLogin(match)
    }
}
