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
                Section {
                    TextField("E-Mail", text: $email)
                        .keyboardType(.emailAddress)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } footer: {
                    Text("Wir schicken dir einen Link. Öffne ihn auf diesem iPhone, um ein neues Passwort festzulegen.")
                }
                if sent {
                    Label("E-Mail ist unterwegs. Bitte schau in dein Postfach.", systemImage: "envelope.badge")
                }
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(Theme.Palette.warning)
                }
            }
            .navigationTitle("Passwort vergessen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(sent ? "Fertig" : "Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Link senden") { Task { await send() } }
                        .disabled(isWorking || !Validation.isPlausibleEmail(email))
                }
            }
        }
    }

    private func send() async {
        errorMessage = nil
        isWorking = true
        defer { isWorking = false }
        do {
            try await SupabaseAuthService.resetPassword(
                email: email.trimmingCharacters(in: .whitespaces).lowercased())
            sent = true
        } catch {
            errorMessage = AuthErrorMessage.text(for: error)
        }
    }
}
