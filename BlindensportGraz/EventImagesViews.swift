import SwiftUI
import PhotosUI
import UIKit

/// Downscales/compresses picked photo library assets before they ever hit
/// SwiftData or CloudKit — raw Photos exports (HEIC, multi-MB) would bloat
/// local storage and CKAsset uploads otherwise.
enum ImageProcessing {
    static func downscaledJPEGData(from data: Data, maxDimension: CGFloat = 1600, quality: CGFloat = 0.7) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let size = image.size
        let scale = min(1, maxDimension / max(size.width, size.height))
        let targetSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        return resized.jpegData(compressionQuality: quality)
    }
}

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
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets())
                .padding(4)
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

struct EventImageGalleryView: View {
    let images: [EventImage]
    let currentUser: User?
    let onDelete: (EventImage) -> Void
    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 4)]

    private func canDelete(_ image: EventImage) -> Bool {
        guard let user = currentUser else { return false }
        return user.role == "admin" || image.uploadedBy == user.id.uuidString
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
