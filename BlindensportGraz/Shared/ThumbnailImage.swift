import SwiftUI

/// Shows a stored photo as a thumbnail sized for its frame. The photo data is
/// read and shrunk once per `id`, not on every redraw; a neutral placeholder
/// shows meanwhile. Callers add the accessibility label.
struct ThumbnailImage: View {
    /// Identifies the photo; a new id loads a new thumbnail.
    let id: UUID
    /// The longest side the image is shown at, in points.
    let maxPointSize: CGFloat
    var contentMode: ContentMode = .fill
    /// Reads the photo data (e.g. a SwiftData external-storage property) —
    /// called once per `id`, not during layout.
    let data: () -> Data

    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                Rectangle().fill(.quaternary)
            }
        }
        // One image element whether the placeholder or the photo is shown,
        // so the caller's label (or hidden state) always applies.
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isImage)
        .task(id: id) {
            image = await Thumbnail.make(from: data(), maxPixelSize: maxPointSize * displayScale)
        }
    }
}
