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
                FormTitleHeader(title: "Neues Konto")
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
                    FormActionButtons(primaryTitle: nil, cancelTitle: "Fertig", onCancel: { dismiss() })
                } else {
                    Section {
                        StackedField(label: "Vorname", text: $firstName)
                            .textContentType(.givenName)
                        StackedField(label: "Nachname", text: $lastName)
                            .textContentType(.familyName)
                        StackedField(label: "E-Mail", text: $email)
                            .keyboardType(.emailAddress)
                            .textContentType(.username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        if !email.isEmpty, !Validation.isPlausibleEmail(email) {
                            Label("Ungültige E-Mail-Adresse", systemImage: "exclamationmark.triangle")
                                .font(.callout)
                                .foregroundStyle(Theme.Palette.warning)
                        }
                    } header: {
                        SectionHeading("Konto")
                    }
                    Section {
                        StackedField(label: "Passwort", text: $password, secure: true)
                            .textContentType(.newPassword)
                        StackedField(label: "Passwort wiederholen", text: $passwordConfirm, secure: true)
                            .textContentType(.newPassword)
                        if !password.isEmpty, !Validation.passwordMeetsMinimumStrength(password) {
                            Label("Mindestens 10 Zeichen, mit Buchstaben und Ziffern", systemImage: "exclamationmark.triangle")
                                .font(.callout)
                                .foregroundStyle(Theme.Palette.warning)
                        }
                        if !passwordConfirm.isEmpty, password != passwordConfirm {
                            Label("Passwörter stimmen nicht überein", systemImage: "exclamationmark.triangle")
                                .font(.callout)
                                .foregroundStyle(Theme.Palette.warning)
                        }
                        if let errorMessage {
                            Label(errorMessage, systemImage: "exclamationmark.triangle")
                                .font(.callout)
                                .foregroundStyle(Theme.Palette.warning)
                        }
                    } header: {
                        SectionHeading("Passwort")
                    }
                    FormActionButtons(primaryTitle: "Erstellen", cancelTitle: "Abbrechen", isWorking: isCreating,
                                      onPrimary: submit, onCancel: { dismiss() })
                }
            }
        }
    }

    /// What's missing before creating the account, in German; nil if nothing.
    static func missingInput(firstName: String, lastName: String, email: String,
                             password: String, passwordConfirm: String) -> String? {
        if firstName.trimmingCharacters(in: .whitespaces).isEmpty { return String(localized: "Bitte gib deinen Vornamen ein.") }
        if lastName.trimmingCharacters(in: .whitespaces).isEmpty { return String(localized: "Bitte gib deinen Nachnamen ein.") }
        if !Validation.isPlausibleEmail(email) { return String(localized: "Bitte gib eine gültige E-Mail-Adresse ein.") }
        if !Validation.passwordMeetsMinimumStrength(password) {
            return String(localized: "Das Passwort braucht mindestens 10 Zeichen, mit Buchstaben und Ziffern.")
        }
        if password != passwordConfirm { return String(localized: "Die beiden Passwörter stimmen nicht überein.") }
        return nil
    }

    private func submit() {
        guard !isCreating else { return }
        if let missing = Self.missingInput(firstName: firstName, lastName: lastName, email: email,
                                           password: password, passwordConfirm: passwordConfirm) {
            show(missing)
            return
        }
        Task { await create() }
    }

    /// Shown in the form and read out, as it appears away from the VoiceOver cursor.
    private func show(_ message: String) {
        errorMessage = message
        AccessibilityNotification.Announcement(message).post()
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
            show(AuthErrorMessage.text(for: error))
        }
    }
}
