import SwiftUI
import SwiftData
import AuthenticationServices

struct RegisterView: View {
    let onRegister: (User) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    // Intentionally unfiltered — only ever read via `users.isEmpty` (the
    // very-first-account bootstrap check below), which needs the full set
    // to answer correctly.
    @Query private var users: [User]

    @State private var email = ""
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var password = ""
    @State private var passwordConfirm = ""
    @State private var isCreating = false

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
                            .foregroundStyle(.orange)
                    }
                }
                Section("Passwort") {
                    SecureField("Passwort", text: $password)
                    SecureField("Passwort wiederholen", text: $passwordConfirm)
                    if !password.isEmpty, !Validation.passwordMeetsMinimumStrength(password) {
                        Label("Passwort muss mindestens 8 Zeichen haben", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    if !passwordConfirm.isEmpty, password != passwordConfirm {
                        Label("Passwörter stimmen nicht überein", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
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
                        Task {
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
