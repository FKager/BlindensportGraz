import SwiftUI
import SwiftData
import AuthenticationServices

struct RegisterView: View {
    let onRegister: (User) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    // Intentionally unfiltered — read for the very-first-account bootstrap
    // check and the duplicate-email check below, which need the full set.
    @Query private var users: [User]

    @State private var email = ""
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var password = ""
    @State private var passwordConfirm = ""
    @State private var isCreating = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Konto") {
                    TextField("Vorname", text: $firstName)
                    TextField("Nachname", text: $lastName)
                    TextField("E-Mail", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if !Validation.isPlausibleEmail(email) {
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
            .navigationTitle("Neues Konto")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Erstellen") {
                        isCreating = true
                        errorMessage = nil
                        Task {
                            // Emails must be unique: they identify accounts at
                            // login and the club's root account. Checked locally
                            // AND in CloudKit (this device may not be synced) —
                            // registration needs a connection for that check.
                            if AccessPolicy.isEmailTaken(email, by: users) {
                                errorMessage = String(localized: "Für diese E-Mail-Adresse gibt es bereits ein Konto. Bitte melde dich an.")
                                isCreating = false
                                return
                            }
                            switch await SyncOrchestrationService.userIdentityExists(email: email) {
                            case .some(true):
                                errorMessage = String(localized: "Für diese E-Mail-Adresse gibt es bereits ein Konto. Bitte melde dich an.")
                                isCreating = false
                                return
                            case .none:
                                errorMessage = String(localized: "Keine Verbindung zu iCloud. Bitte versuche es später noch einmal.")
                                isCreating = false
                                return
                            case .some(false):
                                break
                            }
                            let salt = PasswordHashing.makeSalt()
                            let user = User(email: email, firstName: firstName, lastName: lastName,
                                             passwordHash: PasswordHashing.hash(password: password, salt: salt),
                                             passwordSalt: salt)
                            // The very first account ever created (locally and in CloudKit) becomes
                            // root and admin — otherwise it'd be locked out of the admin features
                            // it needs to set up the club in the first place.
                            if users.isEmpty, !(await SyncOrchestrationService.hasAnyUserIdentity()) {
                                user.isRoot = true
                                user.role = .admin
                            }
                            let oldRole = user.role
                            let becameDesignatedRoot = user.elevateIfDesignatedRoot()
                            modelContext.insert(user)
                            Member.checkMembership(for: user, modelContext: modelContext)
                            UserService.save(user, modelContext: modelContext)
                            if becameDesignatedRoot {
                                RoleChangeLogService.log(userID: user.id, oldRole: oldRole.rawValue, newRole: user.role.rawValue,
                                                          changedBy: "system:designatedRoot", modelContext: modelContext)
                            }
                            dismiss()
                            onRegister(user)
                        }
                    }
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
