import SwiftUI

/// A circular profile photo, or a symbol when there is none.
struct ProfilePhotoImage: View {
    let photo: Data?
    let fallback: String

    var body: some View {
        if let photo, let image = UIImage(data: photo) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .clipShape(Circle())
        } else {
            Image(systemName: fallback)
                .resizable()
                .scaledToFit()
                .foregroundStyle(.secondary)
        }
    }
}
