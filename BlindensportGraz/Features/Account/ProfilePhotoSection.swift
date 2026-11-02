import SwiftUI
import PhotosUI

/// The signed-in account's profile photo (Supabase bucket `profile-photos`),
/// attached to the GVSC Beitrittserklärung mail. Picking uploads right away;
/// `photo` mirrors what is stored so the caller can show it elsewhere.
struct ProfilePhotoSection: View {
    let userID: UUID
    @Binding var photo: Data?
    var footer: LocalizedStringKey = "Wird der Beitrittserklärung zum Grazer VSC beigelegt."

    @State private var selectedItem: PhotosPickerItem?
    @State private var isBusy = false
    @State private var errorMessage: String?

    var body: some View {
        Section {
            HStack(spacing: Theme.Spacing.l) {
                ProfilePhotoImage(photo: photo, fallback: "person.crop.circle")
                    .frame(width: 64, height: 64)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    PhotosPicker(selection: $selectedItem, matching: .images) {
                        Label(photo == nil ? "Foto auswählen" : "Foto ändern", systemImage: "photo")
                    }
                    if photo != nil {
                        Button(role: .destructive) {
                            Task { await remove() }
                        } label: {
                            Label("Foto entfernen", systemImage: "trash")
                        }
                    }
                }
                .disabled(isBusy)
                if isBusy { ProgressView() }
            }
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.warning)
            }
        } header: {
            Text("Profilfoto")
        } footer: {
            Text(footer)
        }
        .onChange(of: selectedItem) { _, item in
            guard let item else { return }
            Task { await upload(item) }
        }
    }

    private func upload(_ item: PhotosPickerItem) async {
        errorMessage = nil
        isBusy = true
        defer {
            isBusy = false
            selectedItem = nil
        }
        guard let raw = try? await item.loadTransferable(type: Data.self),
              let jpeg = ImageProcessing.downscaledJPEGData(from: raw, maxDimension: 1200, quality: 0.8) else {
            errorMessage = String(localized: "Das Foto konnte nicht gelesen werden.")
            return
        }
        do {
            try await SupabaseProfileService.uploadPhoto(jpeg, userID: userID)
            photo = jpeg
        } catch {
            errorMessage = AuthErrorMessage.text(for: error)
        }
    }

    private func remove() async {
        errorMessage = nil
        isBusy = true
        defer { isBusy = false }
        do {
            try await SupabaseProfileService.deletePhoto(userID: userID)
            photo = nil
        } catch {
            errorMessage = AuthErrorMessage.text(for: error)
        }
    }
}
