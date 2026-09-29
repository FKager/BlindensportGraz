import SwiftUI
import PhotosUI
import UIKit

struct EventImageGalleryView: View {
    let images: [EventImage]
    let currentUser: User?
    let onDelete: (EventImage) -> Void
    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.adaptive(minimum: 100), spacing: Theme.Spacing.xs)]

    private func canDelete(_ image: EventImage) -> Bool {
        guard let user = currentUser else { return false }
        return user.role == .admin || image.uploadedBy == user.id.uuidString
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: Theme.Spacing.xs) {
                    ForEach(images.sorted { $0.uploadedAt > $1.uploadedAt }) { image in
                        if let uiImage = UIImage(data: image.imageData) {
                            ZStack(alignment: .topTrailing) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(height: 100)
                                    .frame(maxWidth: .infinity)
                                    .clipped()
                                    .accessibilityLabel("Bild vom \(image.uploadedAt.formatted(date: .abbreviated, time: .shortened))")

                                if canDelete(image) {
                                    Button {
                                        onDelete(image)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .symbolRenderingMode(.palette)
                                            .foregroundStyle(.white, .black.opacity(0.6))
                                            .padding(Theme.Spacing.xs)
                                            // 44×44 pt minimum tap target.
                                            .frame(minWidth: 44, minHeight: 44)
                                            .contentShape(.rect)
                                    }
                                    .accessibilityLabel("Bild löschen")
                                }
                            }
                        }
                    }
                }
                .padding(Theme.Spacing.xs)
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
