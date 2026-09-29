import SwiftUI
import SwiftData

struct EditAccountView: View {
    @Bindable var user: User
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var allUsers: [User]

    // Snapshot of the fields this screen actually lets you edit, captured
    // when the screen appears (bug-373 follow-up). `onDisappear` used to
    // unconditionally push the WHOLE user record — including `role`/`isRoot`,
    // neither of which this screen ever touches — even when nothing was
    // edited. That's a real clobber risk: if this screen's local `user`
    // object still held a role from before a role change made elsewhere
    // (e.g. an admin promotion via rootcli, or another device) simply
    // opening and closing "Profil bearbeiten" would push that stale role
    // straight back to CloudKit, silently undoing the promotion. Only push
    // when firstName/lastName/email actually changed.
    @State private var originalFirstName = ""
    @State private var originalLastName = ""
    @State private var originalEmail = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Profil") {
                    TextField("Vorname", text: $user.firstName)
                    TextField("Nachname", text: $user.lastName)
                    TextField("E-Mail", text: $user.email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    // Advisory only, deliberately never blocks Fertig/dismiss (unlike
                    // nameIsBlank below) — an already-malformed pre-existing email
                    // must stay viewable/editable, not lock the user out of this sheet.
                    if !Validation.isPlausibleEmail(user.email) {
                        Label("Ungültige E-Mail-Adresse", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(Theme.Palette.warning)
                    }
                    if emailIsTaken {
                        Label("Diese E-Mail-Adresse wird bereits von einem anderen Konto verwendet.",
                              systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(Theme.Palette.warning)
                    }
                }
                Section {
                    LabeledContent("Rolle", value: roleLabel(user.role.rawValue))
                    Text("Die Rolle kann nur von einem Root-Benutzer geändert werden.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Profil bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                        .disabled(nameIsBlank || emailIsTaken)
                }
            }
            // Blocks swipe-to-dismiss too, not just the toolbar button — a
            // blank name here silently drops from every export that shows
            // this person (e.g. Trainingsfrequenzliste), unlike every other
            // name-entry point in the app (RegisterView, AddMemberView),
            // which already disable their save action the same way.
            .interactiveDismissDisabled(nameIsBlank || emailIsTaken)
            // No root grant here any more: typing the club account's name and
            // email into your own profile used to make you root + admin on
            // the spot. The club account already exists, and emails are now
            // unique, so the grant only happens where that account is created
            // or signs in (RegisterView, RootView).
            .onAppear {
                originalFirstName = user.firstName
                originalLastName = user.lastName
                originalEmail = user.email
            }
            .onDisappear {
                guard user.firstName != originalFirstName
                    || user.lastName != originalLastName
                    || user.email != originalEmail else { return }
                UserService.save(user, modelContext: modelContext)
            }
        }
    }

    /// Emails identify accounts (login, the club's root account), so they
    /// must stay unique.
    private var emailIsTaken: Bool {
        user.email != originalEmail && AccessPolicy.isEmailTaken(user.email, by: allUsers, except: user)
    }

    private var nameIsBlank: Bool {
        user.firstName.trimmingCharacters(in: .whitespaces).isEmpty ||
        user.lastName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func roleLabel(_ role: String) -> String {
        switch role {
        case "admin": return "Administrator"
        case "coach": return "Trainer:in"
        default: return "Mitglied"
        }
    }
}
