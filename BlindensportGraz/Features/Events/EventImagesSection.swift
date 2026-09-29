import SwiftUI
import PhotosUI
import UIKit

/// Random-photo banner + upload + full gallery, embeddable in any Event/
/// Training/Tournament detail view. Works purely off a resolved `[EventImage]`
/// array and add/delete closures so it doesn't need to know which of the three
/// entity types owns the photos — the caller supplies that via the closures.
struct EventImagesSection: View {
    let images: [EventImage]
    let currentUser: User?
    let onAdd: (Data) -> Void
    let onDelete: (EventImage) -> Void

    @State private var featured: EventImage?
    @State private var showGallery = false
    @State private var selectedItems: [PhotosPickerItem] = []

    var body: some View {
        Section("Bilder (\(images.count))") {
            if let featured, let uiImage = UIImage(data: featured.imageData) {
                Button {
                    showGallery = true
                } label: {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 180)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets())
                .padding(Theme.Spacing.xs)
            } else if images.isEmpty {
                Text("Noch keine Bilder")
                    .foregroundStyle(.secondary)
            }

            HStack {
                if !images.isEmpty {
                    Button("Alle anzeigen") { showGallery = true }
                }
                Spacer()
                PhotosPicker(selection: $selectedItems, matching: .images) {
                    Label("Hinzufügen", systemImage: "photo.badge.plus")
                }
            }
        }
        .onAppear {
            if featured == nil { featured = images.randomElement() }
        }
        .onChange(of: images.count) {
            featured = images.randomElement()
        }
        .onChange(of: selectedItems) { _, items in
            guard !items.isEmpty else { return }
            Task {
                for item in items {
                    if let raw = try? await item.loadTransferable(type: Data.self),
                       let compressed = ImageProcessing.downscaledJPEGData(from: raw) {
                        onAdd(compressed)
                    }
                }
                selectedItems = []
            }
        }
        .sheet(isPresented: $showGallery) {
            EventImageGalleryView(images: images, currentUser: currentUser, onDelete: onDelete)
        }
    }
}
