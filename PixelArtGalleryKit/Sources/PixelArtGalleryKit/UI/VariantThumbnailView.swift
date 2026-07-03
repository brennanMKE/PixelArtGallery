import SwiftUI

/// Renders a variant's pixel art (its RGBA8888 grid) as a crisp, nearest-neighbor
/// thumbnail. Mirrors `StoredImageView`: the grid is turned into a `CGImage` off the
/// main actor, and a placeholder shows until it's ready. `.interpolation(.none)` keeps
/// the pixels hard-edged when the small image is scaled up into the thumbnail frame.
struct VariantThumbnailView: View {
    let variant: Variant

    @State private var image: Image?

    var body: some View {
        Group {
            if let image {
                image
                    .interpolation(.none)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                    .fill(.quaternary)
                    .overlay {
                        Image(systemName: "square.grid.3x3.fill")
                            .foregroundStyle(.tertiary)
                    }
            }
        }
        // Re-render when the variant or its dimensions change (e.g. after an edit).
        .task(id: "\(variant.id)-\(variant.targetWidth)x\(variant.targetHeight)") {
            await render()
        }
    }

    private func render() async {
        // Read the SwiftData @Model fields on the main actor, then render off-main.
        let width = variant.targetWidth
        let height = variant.targetHeight
        let data = variant.pixelGridData

        let rendered = await Task.detached(priority: .userInitiated) { () -> SendableCGImage? in
            guard let grid = try? PixelGrid.fromRGBA8888(data, width: width, height: height),
                  let cg = grid.makeCGImage() else {
                return nil
            }
            return SendableCGImage(cgImage: cg)
        }.value

        guard !Task.isCancelled, let rendered else { return }
        image = Image(decorative: rendered.cgImage, scale: 1.0)
    }
}
