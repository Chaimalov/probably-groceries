import SwiftUI
import UIKit

struct ItemPhotoThumbnail: View {
    let bytes: Data?
    let fileURL: URL?
    let name: String
    let side: CGFloat
    let fullImage: Bool
    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?
    @State private var finished = false

    init(bytes: Data?, fileURL: URL?, name: String, side: CGFloat = 36, fullImage: Bool = false) {
        self.bytes = bytes; self.fileURL = fileURL; self.name = name
        self.side = side; self.fullImage = fullImage
    }

    private struct Source: Hashable, Sendable {
        let bytes: Data?
        let fileURL: URL?
        let pixels: CGFloat
        let fullImage: Bool
    }

    var body: some View {
        let source = Source(bytes: bytes, fileURL: fileURL, pixels: side * displayScale, fullImage: fullImage)
        Group {
            if let image {
                if fullImage {
                    Image(uiImage: image).resizable().scaledToFit()
                        .accessibilityLabel("תמונה של \(name)")
                } else {
                    Image(uiImage: image).resizable().scaledToFill()
                        .frame(width: side, height: side)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .accessibilityLabel("תמונה של \(name)")
                }
            } else if !finished {
                if fullImage { ProgressView("טוען תמונה") }
                else {
                    Image(systemName: "photo").foregroundStyle(.secondary)
                        .frame(width: side, height: side).accessibilityHidden(true)
                }
            } else if fullImage {
                ContentUnavailableView("התמונה אינה זמינה", systemImage: "photo")
            }
        }
        .task(id: source) {
            image = nil
            finished = false
            let work = Task.detached(priority: .utility) { () -> UIImage? in
                guard !Task.isCancelled else { return nil }
                let data = source.bytes ?? source.fileURL.flatMap { try? Data(contentsOf: $0) }
                guard !Task.isCancelled, let data, let original = UIImage(data: data) else { return nil }
                if source.fullImage { return await original.byPreparingForDisplay() }
                return await original.byPreparingThumbnail(ofSize: CGSize(width: source.pixels, height: source.pixels))
            }
            let prepared = await withTaskCancellationHandler(operation: {
                await work.value
            }, onCancel: { work.cancel() })
            guard !Task.isCancelled else { return }
            image = prepared
            finished = true
        }
    }
}
