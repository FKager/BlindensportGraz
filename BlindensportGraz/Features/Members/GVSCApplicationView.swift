import SwiftUI
import SwiftData
import QuickLook

/// Fills the GVSC Beitrittserklärung from the Benutzerverwaltung, shows what
/// is still missing, previews the Word file and — after confirmation — has
/// the server mail it (plus the linked account's profile photo) to the club.
///
/// Admins open it from MemberDetailView; members from AccountView for their
/// own approved entry, where `request` is their pending change proposal (if
/// any) so the form shows what they just entered.
struct GVSCApplicationView: View {
    let member: Member
    var request: MemberChangeRequest? = nil
    /// The account whose profile photo is attached; nil if the entry has no
    /// linked account.
    var photoUserID: UUID? = nil
    /// The member's own flow: the photo can be added/changed here.
    var canEditPhoto = false

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var docx: Data?
    @State private var previewURL: URL?
    @State private var photo: Data?
    @State private var photoLoaded = false
    @State private var showSendConfirmation = false
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var sentWithPhoto: Bool?

    private static let recipient = "blindensport.gvsc@gmail.com"

    private var data: GVSCApplicationData {
        if let request { return GVSCApplicationData(request: request, member: member) }
        return GVSCApplicationData(member: member)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Die Beitrittserklärung wird mit den Daten aus der Benutzerverwaltung ausgefüllt und an \(Self.recipient) gesendet. Sie muss danach noch unterschrieben werden.")
                    if let appliedAt = member.gvscAppliedAt {
                        Label("Zuletzt gesendet am \(appliedAt.formatted(date: .abbreviated, time: .shortened))",
                              systemImage: "envelope.badge")
                            .foregroundStyle(.secondary)
                    }
                }

                let missing = data.missingFields
                Section {
                    if missing.isEmpty {
                        Label("Alle Angaben sind ausgefüllt.", systemImage: "checkmark.circle")
                            .foregroundStyle(Theme.Palette.success)
                    } else {
                        ForEach(missing, id: \.self) { field in
                            Label(field, systemImage: "exclamationmark.circle")
                                .foregroundStyle(Theme.Palette.warning)
                        }
                    }
                } header: {
                    Text("Fehlende Angaben")
                } footer: {
                    if !missing.isEmpty {
                        Text(canEditPhoto
                             ? "Ergänze die Angaben unter „Vereinsdaten bearbeiten“. Fehlendes kann auch auf dem Papierformular nachgetragen werden."
                             : "Ergänze die Angaben in der Benutzerverwaltung. Fehlendes kann auch auf dem Papierformular nachgetragen werden.")
                    }
                }

                if let photoUserID, canEditPhoto {
                    ProfilePhotoSection(userID: photoUserID, photo: $photo)
                } else {
                    Section("Profilfoto") {
                        if !photoLoaded && photoUserID != nil {
                            ProgressView()
                        } else if let photo {
                            HStack(spacing: Theme.Spacing.l) {
                                ProfilePhotoImage(photo: photo, fallback: "person.crop.circle")
                                    .frame(width: 64, height: 64)
                                    .accessibilityHidden(true)
                                Text("Wird mitgesendet.")
                            }
                        } else {
                            Label(photoUserID == nil
                                  ? "Kein verknüpftes Konto — es wird kein Foto mitgesendet."
                                  : "Kein Profilfoto vorhanden.",
                                  systemImage: "person.crop.circle.badge.questionmark")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    Button {
                        previewURL = writePreview()
                    } label: {
                        Label("Vorschau der Beitrittserklärung", systemImage: "doc.text.magnifyingglass")
                    }
                    .disabled(docx == nil)
                    Button {
                        showSendConfirmation = true
                    } label: {
                        if isSending {
                            ProgressView()
                        } else {
                            Label("An den Grazer VSC senden", systemImage: "paperplane")
                        }
                    }
                    .disabled(docx == nil || isSending)
                }
                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Theme.Palette.warning)
                    }
                }
            }
            .navigationTitle("Beitrittserklärung")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schließen") { dismiss() }
                }
            }
            .quickLookPreview($previewURL)
            .confirmationDialog("Beitrittserklärung senden?", isPresented: $showSendConfirmation,
                                titleVisibility: .visible) {
                Button("Senden") { Task { await send() } }
                Button("Abbrechen", role: .cancel) {}
            } message: {
                Text("Die ausgefüllte Beitrittserklärung für \(member.fullName) wird an \(Self.recipient) gesendet.")
            }
            .alert("Beitrittserklärung gesendet", isPresented: Binding(get: { sentWithPhoto != nil },
                                                                      set: { if !$0 { sentWithPhoto = nil; dismiss() } })) {
                Button("OK") {}
            } message: {
                Text(sentWithPhoto == true
                     ? "Die Beitrittserklärung und das Profilfoto wurden gesendet. Ein Admin bestätigt die Mitgliedschaft, sobald das unterschriebene Formular eingelangt ist."
                     : "Die Beitrittserklärung wurde gesendet. Ein Admin bestätigt die Mitgliedschaft, sobald das unterschriebene Formular eingelangt ist.")
            }
            .task { await prepare() }
        }
    }

    private func prepare() async {
        do {
            docx = try GVSCApplicationDocument.makeDocx(data)
        } catch {
            errorMessage = error.localizedDescription
        }
        if let photoUserID {
            photo = await SupabaseProfileService.downloadPhoto(userID: photoUserID)
        }
        photoLoaded = true
    }

    private func writePreview() -> URL? {
        guard let docx else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(GVSCApplicationDocument.fileName(for: data))
        do {
            try docx.write(to: url, options: .atomic)
            return url
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    private func send() async {
        // Rebuilt so it matches the data at the moment of sending.
        guard let current = try? GVSCApplicationDocument.makeDocx(data) else { return }
        errorMessage = nil
        isSending = true
        defer { isSending = false }
        do {
            let withPhoto = try await SupabaseMembershipApplicationService.send(memberID: member.id, docx: current)
            member.gvscAppliedAt = .now
            try? modelContext.save()
            sentWithPhoto = withPhoto
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
