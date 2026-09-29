import SwiftUI
import PhotosUI
import UIKit

struct EventImageGalleryView: View {
    let images: [EventImage]
    let currentUser: User?
    let onDelete: (EventImage) -> Void
    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 4)]

    private func canDelete(_ image: EventImage) -> Bool {
        guard let user = currentUser else { return false }
        return user.role == .admin || image.uploadedBy == user.id.uuidString
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(images.sorted { $0.uploadedAt > $1.uploadedAt }) { image in
                        if let uiImage = UIImage(data: image.imageData) {
                            ZStack(alignment: .topTrailing) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(height: 100)
                                    .frame(maxWidth: .infinity)
                                    .clipped()

                                if canDelete(image) {
                                    Button {
                                        onDelete(image)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .symbolRenderingMode(.palette)
                                            .foregroundStyle(.white, .black.opacity(0.6))
                                            .padding(4)
                                    }
                                    .accessibilityLabel("Bild löschen")
                                }
                            }
                        }
                    }
                }
                .padding(4)
            }
            .navigationTitle("Bilder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
            .overlay {
                if images.isEmpty {
                    ContentUnavailableView("Keine Bilder", systemImage: "photo")
                }
            }
        }
    }
}
