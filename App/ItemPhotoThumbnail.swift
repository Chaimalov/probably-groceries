import SwiftUI
import UIKit

struct ItemPhotoThumbnail: View {
    let bytes: Data?
    let fileURL: URL?
    let name: String
    var side: CGFloat = 36
    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?
    @State private var finished = false

    private struct Source: Hashable {
        let bytes: Data?
        let fileURL: URL?
        let pixels: CGFloat
    }

    var body: some View {
        let source = Source(bytes: bytes, fileURL: fileURL, pixels: side * displayScale)
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
                    .frame(width: side, height: side)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .accessibilityLabel("תמונה של \(name)")
            } else if !finished {
                Image(systemName: "photo").foregroundStyle(.secondary)
                    .frame(width: side, height: side).accessibilityHidden(true)
            }
        }
        .task(id: source) {
            image = nil
            finished = false
            let prepared = await Task.detached(priority: .utility) { () -> UIImage? in
                let data = source.bytes ?? source.fileURL.flatMap { try? Data(contentsOf: $0) }
                guard let data, let original = UIImage(data: data) else { return nil }
                return await original.byPreparingThumbnail(ofSize: CGSize(width: source.pixels, height: source.pixels))
            }.value
            guard !Task.isCancelled else { return }
            image = prepared
            finished = true
        }
    }
}
