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
                FormTitleHeader(title: "Anmelden")
                Section {
                    StackedField(label: "E-Mail", text: $email)
                        .keyboardType(.emailAddress)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    StackedField(label: "Passwort", text: $password, secure: true)
                        .textContentType(.password)
                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .font(.callout)
                            .foregroundStyle(Theme.Palette.warning)
                    }
                }
                FormActionButtons(primaryTitle: "Anmelden", cancelTitle: "Abbrechen", isWorking: isWorking,
                                  onPrimary: login, onCancel: { dismiss() })
                Section {
                    Button("Passwort vergessen?") { showReset = true }
                    Button("Mit Apple anmelden") { Task { await signInWithApple() } }
                        .disabled(isWorking)
                    Button("Neues Konto erstellen") { showRegister = true }
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

    /// What's missing before signing in, in German; nil if nothing.
    static func missingInput(email: String, password: String) -> String? {
        if email.trimmingCharacters(in: .whitespaces).isEmpty { return String(localized: "Bitte gib deine E-Mail-Adresse ein.") }
        if password.isEmpty { return String(localized: "Bitte gib dein Passwort ein.") }
        return nil
    }

    private func login() {
        guard !isWorking else { return }
        if let missing = Self.missingInput(email: email, password: password) {
            show(missing)
            return
        }
        Task { await attemptLogin() }
    }

    /// Shown in the form and read out, as it appears away from the VoiceOver cursor.
    private func show(_ message: String) {
        errorMessage = message
        AccessibilityNotification.Announcement(message).post()
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
            show(AuthErrorMessage.text(for: error))
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
            show(AuthErrorMessage.text(for: error))
        }
    }
}
