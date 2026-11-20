import XCTest
import UIKit
@testable import BlindensportGraz

/// Gallery, banner and receipt thumbnails: a large photo comes back no larger
/// than requested, keeps its aspect ratio, and non-image data fails cleanly.
final class ThumbnailTests: XCTestCase {
    private func jpeg(width: CGFloat, height: CGFloat) throws -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        return try XCTUnwrap(image.jpegData(compressionQuality: 0.8))
    }

    func testLargePhotoIsShrunkToTheRequestedSize() async throws {
        let data = try jpeg(width: 3000, height: 1500)

        let result = await Thumbnail.make(from: data, maxPixelSize: 300)
        let thumbnail = try XCTUnwrap(result)
        let cgImage = try XCTUnwrap(thumbnail.cgImage)

        XCTAssertEqual(cgImage.width, 300)
        XCTAssertEqual(cgImage.height, 150)
    }

    func testSmallPhotoIsNotEnlarged() async throws {
        let data = try jpeg(width: 120, height: 80)

        let result = await Thumbnail.make(from: data, maxPixelSize: 300)
        let thumbnail = try XCTUnwrap(result)

        XCTAssertLessThanOrEqual(try XCTUnwrap(thumbnail.cgImage).width, 120)
    }

    func testNonImageDataGivesNoThumbnail() async {
        let image = await Thumbnail.make(from: Data("kein Bild".utf8), maxPixelSize: 300)
        XCTAssertNil(image)
    }
}
