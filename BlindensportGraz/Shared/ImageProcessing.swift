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
