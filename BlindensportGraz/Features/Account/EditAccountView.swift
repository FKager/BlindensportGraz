import SwiftUI
import SwiftData

struct EditAccountView: View {
    @Bindable var user: User
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

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
                            .foregroundStyle(.orange)
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
                        .disabled(nameIsBlank)
                }
            }
            // Blocks swipe-to-dismiss too, not just the toolbar button — a
            // blank name here silently drops from every export that shows
            // this person (e.g. Trainingsfrequenzliste), unlike every other
            // name-entry point in the app (RegisterView, AddMemberView),
            // which already disable their save action the same way.
            .interactiveDismissDisabled(nameIsBlank)
            // Catches the case where firstName/lastName/email are edited into a
            // match for the club's designated root account (Models.swift's
            // elevateIfDesignatedRoot) -- that account is always created manually,
            // so this is the only place besides creation where the grant can fire.
            .onChange(of: user.firstName) { _, _ in applyDesignatedRootGrantIfNeeded() }
            .onChange(of: user.lastName) { _, _ in applyDesignatedRootGrantIfNeeded() }
            .onChange(of: user.email) { _, _ in applyDesignatedRootGrantIfNeeded() }
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

    private func applyDesignatedRootGrantIfNeeded() {
        let oldRole = user.role
        if user.elevateIfDesignatedRoot() {
            UserService.save(user, modelContext: modelContext)
            RoleChangeLogService.log(userID: user.id, oldRole: oldRole.rawValue, newRole: user.role.rawValue,
                                      changedBy: "system:designatedRoot", modelContext: modelContext)
        }
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
