import SwiftUI
import AuthenticationServices

/// Email + password or Sign in with Apple, both against Supabase Auth.
/// `AuthContext` picks up the new session and switches the root screen.
struct LoginView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var password = ""
    @State private var errorMessage: String?
    @State private var isWorking = false
    @State private var showRegister = false
    @State private var showReset = false

    private let appleSignIn = AppleSignInCoordinator()

    var body: some View {
        NavigationStack {
            Form {
                Section("Anmelden") {
                    TextField("E-Mail", text: $email)
                        .keyboardType(.emailAddress)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Passwort", text: $password)
                        .textContentType(.password)
                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(Theme.Palette.warning)
                    }
                    Button("Anmelden") { Task { await attemptLogin() } }
                        .disabled(isWorking || email.trimmingCharacters(in: .whitespaces).isEmpty || password.isEmpty)
                    Button("Passwort vergessen?") { showReset = true }
                }
                Section {
                    Button("Mit Apple anmelden") { Task { await signInWithApple() } }
                        .disabled(isWorking)
                }
                Section {
                    Button("Neues Konto erstellen") { showRegister = true }
                }
            }
            .navigationTitle("Anmelden")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
            .sheet(isPresented: $showRegister) {
                RegisterView()
            }
            .sheet(isPresented: $showReset) {
                ResetPasswordRequestView(email: email)
            }
        }
    }

    private func attemptLogin() async {
        errorMessage = nil
        isWorking = true
        defer { isWorking = false }
        do {
            try await SupabaseAuthService.signIn(
                email: email.trimmingCharacters(in: .whitespaces).lowercased(), password: password)
            dismiss()
        } catch {
            errorMessage = AuthErrorMessage.text(for: error)
        }
    }

    private func signInWithApple() async {
        errorMessage = nil
        isWorking = true
        defer { isWorking = false }
        do {
            try await AppleSupabaseSignIn.run(using: appleSignIn)
            dismiss()
        } catch where AppleSupabaseSignIn.isCancellation(error) {
            return
        } catch {
            errorMessage = AuthErrorMessage.text(for: error)
        }
    }
}
