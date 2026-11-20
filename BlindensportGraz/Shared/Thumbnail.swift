import ImageIO
import UIKit

/// Small display copies of stored photos. ImageIO reads only as much of the
/// file as the requested size needs, instead of decoding the full photo.
enum Thumbnail {
    /// A copy whose longer side is at most `maxPixelSize`, rotated upright;
    /// nil if `data` is not an image. Runs off the main thread.
    @concurrent
    nonisolated static func make(from data: Data, maxPixelSize: CGFloat) async -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixelSize)
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }
}
