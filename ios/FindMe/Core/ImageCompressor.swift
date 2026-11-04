import UIKit

/// N-08 / N-10: long edge ≤ 2048 px, ≤ 1 MB JPEG. Re-rendering through UIGraphicsImageRenderer and
/// re-encoding from a bitmap drops all EXIF/GPS metadata from the original capture.
enum ImageCompressor {
    static func jpeg(from image: UIImage, maxLongEdge: CGFloat = 2048, maxBytes: Int = 1_000_000) -> Data? {
        var edge = maxLongEdge
        for _ in 0..<6 {
            let resized = resize(image, maxLongEdge: edge)
            for quality in stride(from: 0.85, through: 0.35, by: -0.1) {
                if let data = resized.jpegData(compressionQuality: quality), data.count <= maxBytes {
                    return data
                }
            }
            edge *= 0.8
        }
        return nil
    }

    /// Center-crops to a square of `side` px (avatars). Re-rendering also strips EXIF.
    static func squareAvatar(from image: UIImage, side: CGFloat = 512, maxBytes: Int = 400_000) -> Data? {
        let size = image.size
        let short = min(size.width, size.height)
        guard short > 0 else { return nil }
        let scale = side / short
        let drawSize = CGSize(width: size.width * scale, height: size.height * scale)
        let origin = CGPoint(x: (side - drawSize.width) / 2, y: (side - drawSize.height) / 2)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let square = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            image.draw(in: CGRect(origin: origin, size: drawSize))
        }
        return jpeg(from: square, maxLongEdge: side, maxBytes: maxBytes)
    }

    static func resize(_ image: UIImage, maxLongEdge: CGFloat) -> UIImage {
        let size = image.size
        let longEdge = max(size.width, size.height)
        let scale = min(1, maxLongEdge / max(longEdge, 1))
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
