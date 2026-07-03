import CoreGraphics
import ImageIO
import SwiftUI

/// Downsamples encoded image data to a `CGImage` no larger than `maxPixelSize`
/// on its longest edge using ImageIO, which decodes at the reduced size rather
/// than fully decoding the original — cheap even for very large photos.
///
/// `nonisolated` so it can run off the main actor inside a detached task.
enum StoredImageDecoder {
    nonisolated static func downsample(_ data: Data, maxPixelSize: CGFloat) -> CGImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixelSize),
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}

/// Asynchronously loads a stored original image by its `originalImagePath` through
/// the coordinator and renders it (downsampled to `maxPixelSize`), falling back to
/// `placeholder` while loading or when the file can't be read or decoded.
struct StoredImageView<Placeholder: View>: View {
    let path: String
    let maxPixelSize: CGFloat
    let coordinator: GalleryCoordinator
    var contentMode: ContentMode = .fill
    @ViewBuilder var placeholder: () -> Placeholder

    @State private var image: Image?

    var body: some View {
        Group {
            if let image {
                image
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                placeholder()
            }
        }
        .task(id: path) {
            await load()
        }
    }

    private func load() async {
        image = nil
        guard !path.isEmpty,
              let data = await coordinator.loadOriginalImageData(path: path) else {
            return
        }
        let target = maxPixelSize
        let decoded = await Task.detached(priority: .userInitiated) { () -> SendableCGImage? in
            guard let cg = StoredImageDecoder.downsample(data, maxPixelSize: target) else {
                return nil
            }
            return SendableCGImage(cgImage: cg)
        }.value

        // Ignore a stale result if the path changed while we were decoding.
        guard !Task.isCancelled, let decoded else { return }
        image = Image(decorative: decoded.cgImage, scale: 1.0)
    }
}
