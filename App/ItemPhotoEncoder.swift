import UIKit

enum ItemPhotoEncoder {
    // JSON base64 adds 1/3 overhead; leave headroom for the remaining record.
    static func encode(_ image: UIImage) -> Data? {
        for longestSide: CGFloat in [1200, 900, 600] {
            let scale = min(1, longestSide / max(max(image.size.width, image.size.height), 1))
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
                image.draw(in: CGRect(origin: .zero, size: size))
            }
            if let bytes = resized.jpegData(compressionQuality: 0.55), bytes.count < 600_000 { return bytes }
        }
        return nil
    }
}
