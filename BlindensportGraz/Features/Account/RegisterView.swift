import SwiftUI

/// Creates a Supabase Auth account. Name goes into the sign-up metadata (the
/// `profiles` row is created by a database trigger). The account starts
/// without a role ("pending") and sees only the schedule until an admin
/// approves it (App-Konten). Email uniqueness is enforced by Supabase.
struct RegisterView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var password = ""
    @State private var passwordConfirm = ""
    @State private var isCreating = false
    @State private var errorMessage: String?
    @State private var awaitingConfirmation = false

    var body: some View {
        NavigationStack {
            Form {
                if awaitingConfirmation {
                    Section {
                        Label("Fast geschafft! Wir haben dir eine E-Mail an \(email) geschickt. Öffne den Link darin auf diesem iPhone, um dein Konto zu bestätigen.",
                              systemImage: "envelope.badge")
                        // Supabase answers "OK" without sending anything when
                        // the address is already registered (no account
                        // enumeration), so point existing users to the reset.
                        Text("Keine E-Mail bekommen? Wenn du schon ein Konto hast (auch aus der früheren App-Version), melde dich nicht neu an, sondern tippe beim Anmelden auf „Passwort vergessen“.")
                            .font(.footnote)
                    }
                } else {
                    Section("Konto") {
                        TextField("Vorname", text: $firstName)
                            .textContentType(.givenName)
                        TextField("Nachname", text: $lastName)
                            .textContentType(.familyName)
                        TextField("E-Mail", text: $email)
                            .keyboardType(.emailAddress)
                            .textContentType(.username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        if !email.isEmpty, !Validation.isPlausibleEmail(email) {
                            Label("Ungültige E-Mail-Adresse", systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundStyle(Theme.Palette.warning)
                        }
                        if let errorMessage {
                            Label(errorMessage, systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundStyle(Theme.Palette.warning)
                        }
                    }
                    Section("Passwort") {
                        SecureField("Passwort", text: $password)
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
                    }
                }
            }
            .navigationTitle("Neues Konto")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(awaitingConfirmation ? "Fertig" : "Abbrechen") { dismiss() }
                }
                if !awaitingConfirmation {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Erstellen") { Task { await create() } }
                            .disabled(isCreating ||
                                      firstName.trimmingCharacters(in: .whitespaces).isEmpty ||
                                      lastName.trimmingCharacters(in: .whitespaces).isEmpty ||
                                      !Validation.isPlausibleEmail(email) ||
                                      !Validation.passwordMeetsMinimumStrength(password) ||
                                      password != passwordConfirm)
                    }
                }
            }
        }
    }

    private func create() async {
        isCreating = true
        errorMessage = nil
        defer { isCreating = false }
        do {
            let response = try await SupabaseAuthService.signUp(
                email: email.trimmingCharacters(in: .whitespaces).lowercased(),
                password: password,
                firstName: firstName.trimmingCharacters(in: .whitespaces),
                lastName: lastName.trimmingCharacters(in: .whitespaces))
            // With email confirmation on, there is no session until the link
            // is opened (AuthContext handles the callback).
            if response.session == nil {
                awaitingConfirmation = true
            } else {
                dismiss()
            }
        } catch {
            errorMessage = AuthErrorMessage.text(for: error)
        }
    }
}
