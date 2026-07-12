import SwiftUI

/// Renders a raw RGBA8888 pixel buffer as a crisp, nearest-neighbor image.
/// The grid is turned into a `CGImage` off the main actor, and a placeholder
/// shows until it's ready. `.interpolation(.none)` keeps the pixels
/// hard-edged when the small image is scaled up.
///
/// Extracted from `VariantThumbnailView` (#0067, which is now a thin wrapper
/// over this view) so the send popover (`GallerySendPopoverView`) can render
/// a transient `FittedPreview`'s grid — which has no persisted `Variant` to
/// key off of — the same way.
struct PixelDataImageView: View {
    let pixelGridData: Data
    let width: Int
    let height: Int

    @State private var image: Image?

    /// Identity for `.task(id:)`: dimensions plus the grid bytes themselves,
    /// so a re-render fires both when the size changes and when the pixels
    /// change at the same size (e.g. re-selecting a different display that
    /// happens to share fit dimensions with the previous one).
    private struct RenderKey: Equatable {
        let width: Int
        let height: Int
        let data: Data
    }

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
        .task(id: RenderKey(width: width, height: height, data: pixelGridData)) {
            await render()
        }
    }

    private func render() async {
        // Capture value-type locals before hopping off-main, mirroring the
        // pattern used for @Model reads elsewhere in the app.
        let width = width
        let height = height
        let data = pixelGridData

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
