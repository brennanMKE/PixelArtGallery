import SwiftUI

/// Renders a variant's pixel art (its RGBA8888 grid) as a crisp, nearest-neighbor
/// thumbnail. Thin wrapper over ``PixelDataImageView`` (extracted in #0067 so the
/// send popover can render a transient `FittedPreview`'s grid the same way).
struct VariantThumbnailView: View {
    let variant: Variant

    var body: some View {
        PixelDataImageView(
            pixelGridData: variant.pixelGridData,
            width: variant.targetWidth,
            height: variant.targetHeight
        )
    }
}
