import SwiftUI
import SwiftData

/// Edits the own name in the Supabase profile (the only client-writable
/// profile columns). Email is the login identity and the role is assigned by
/// root, so both are read-only here.
struct EditAccountView: View {
    @Bindable var user: User
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthContext.self) private var authContext

    @State private var firstName = ""
    @State private var lastName = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Profil") {
                    TextField("Vorname", text: $firstName)
                        .textContentType(.givenName)
                    TextField("Nachname", text: $lastName)
                        .textContentType(.familyName)
                    LabeledContent("E-Mail", value: user.email)
                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(Theme.Palette.warning)
                    }
                }
                Section {
                    LabeledContent("Rolle", value: authContext.role?.displayLabel ?? String(localized: "Freigabe ausstehend"))
                    Text("Die Rolle kann nur von einem Root-Benutzer geändert werden.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Profil bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") { Task { await save() } }
                        .disabled(isSaving || nameIsBlank)
                }
            }
            .onAppear {
                firstName = user.firstName
                lastName = user.lastName
            }
        }
    }

    // A blank name would silently drop this person from exports that list
    // names (e.g. Trainingsfrequenzliste).
    private var nameIsBlank: Bool {
        firstName.trimmingCharacters(in: .whitespaces).isEmpty ||
        lastName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func save() async {
        errorMessage = nil
        isSaving = true
        defer { isSaving = false }
        let first = firstName.trimmingCharacters(in: .whitespaces)
        let last = lastName.trimmingCharacters(in: .whitespaces)
        do {
            try await SupabaseProfileService.updateName(userID: user.id, firstName: first, lastName: last)
            user.firstName = first
            user.lastName = last
            UserService.save(user, modelContext: modelContext)
            dismiss()
        } catch {
            errorMessage = AuthErrorMessage.text(for: error)
        }
    }
}
