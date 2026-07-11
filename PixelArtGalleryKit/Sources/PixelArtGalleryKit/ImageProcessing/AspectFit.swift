import Foundation

/// Pure, integer-only aspect-fit and centering math.
///
/// Given a source image size and a display canvas size, `AspectFit` computes
/// the largest same-aspect-ratio size that fits inside the display ("contain"
/// scaling, matching SwiftUI's `.aspectRatio(contentMode: .fit)`) and the
/// offset that centers that fit size on the display.
///
/// A caseless enum is used purely as a namespace; it is never instantiated.
/// Both the enum and the nested `Placement` are marked `nonisolated` because
/// `Package.swift` default-isolates the main target to `MainActor` — a pure
/// helper consumed from nonisolated tests and off-main-actor callers (the
/// coordinator in #0063) must opt out explicitly rather than rely on that
/// default propagating (this bit #0057/#0060).
nonisolated public enum AspectFit {
    /// The fit dimensions and centering offset of a source placed on a
    /// display canvas.
    ///
    /// Invariant, guaranteed structurally by `fit(sourceWidth:sourceHeight:displayWidth:displayHeight:)`:
    /// `offsetX + width <= displayWidth` and `offsetY + height <= displayHeight`.
    /// Centering can never push the fitted image off the display.
    nonisolated public struct Placement: Equatable, Sendable {
        /// Fit width in pixels, `1...displayWidth`.
        public let width: Int
        /// Fit height in pixels, `1...displayHeight`.
        public let height: Int
        /// Horizontal centering offset, `(displayWidth - width) / 2`, always `>= 0`.
        public let offsetX: Int
        /// Vertical centering offset, `(displayHeight - height) / 2`, always `>= 0`.
        public let offsetY: Int

        public init(width: Int, height: Int, offsetX: Int, offsetY: Int) {
            self.width = width
            self.height = height
            self.offsetX = offsetX
            self.offsetY = offsetY
        }
    }

    /// Compute the largest aspect-preserving size of `sourceWidth x sourceHeight`
    /// that fits inside `displayWidth x displayHeight`, plus the offset that
    /// centers it there.
    ///
    /// **Small-source policy — standard "contain", scale up.** A source smaller
    /// than the display is enlarged until one axis fills the display (e.g. a
    /// 10x5 source into a 45x35 display becomes 45x22, not left at 10x5).
    /// FT displays are small, sources can be small pixel art too, and filling
    /// the display maximizes use of scarce LEDs. This matches SwiftUI's
    /// `.aspectRatio(contentMode: .fit)` semantics already used elsewhere in
    /// the app's previews, and keeps the function a single rule with no
    /// size-comparison branch. #0063/#0064 should treat this as settled policy.
    ///
    /// This function is total: it never throws and never preconditions. Inputs
    /// are clamped to `>= 1` before any math runs, so degenerate (zero or
    /// negative) source/display dimensions yield a safe, well-formed
    /// `Placement` instead of a crash — the values may ultimately come from
    /// user or network data. `PixelationEngine.processFitting` still throws
    /// for invalid display dimensions per its existing contract; the two
    /// behaviors serve different callers.
    ///
    /// - Why the invariant holds structurally (no per-case fixups needed):
    ///   the bound axis is chosen by cross-multiplication, so the *other*
    ///   axis's exact ratio is provably `<=` the display's size on that axis
    ///   before flooring; flooring only shrinks it further, so `fitW <= dispW`
    ///   and `fitH <= dispH` always. Then, since `floor(n / 2) <= n` for any
    ///   `n >= 0`, `offset + fit = floor((disp - fit) / 2) + fit <= (disp - fit) + fit == disp`.
    public static func fit(
        sourceWidth: Int, sourceHeight: Int,
        displayWidth: Int, displayHeight: Int
    ) -> Placement {
        let srcW = max(1, sourceWidth)
        let srcH = max(1, sourceHeight)
        let dispW = max(1, displayWidth)
        let dispH = max(1, displayHeight)

        // Pick the bound axis by cross-multiplication (exact, no rounding
        // error from doing this with floating point). If the source is at
        // least as wide (relative to its height) as the display, the width
        // is the binding constraint. Equality (exact aspect match) folds into
        // this branch — either way fit == display.
        let fitWidth: Int
        let fitHeight: Int
        if srcW * dispH >= srcH * dispW {
            fitWidth = dispW
            fitHeight = max(1, (srcH * dispW) / srcW)
        } else {
            fitHeight = dispH
            fitWidth = max(1, (srcW * dispH) / srcH)
        }

        let offset = centeringOffset(
            imageWidth: fitWidth, imageHeight: fitHeight,
            displayWidth: dispW, displayHeight: dispH
        )

        return Placement(width: fitWidth, height: fitHeight, offsetX: offset.x, offsetY: offset.y)
    }

    /// Compute the offset that centers an `imageWidth x imageHeight` image on
    /// a `displayWidth x displayHeight` canvas.
    ///
    /// This is the single source of truth for the centering arithmetic, shared
    /// by `fit(sourceWidth:sourceHeight:displayWidth:displayHeight:)` above and
    /// by the coordinator (#0063), which centers manually-sized (non-fit)
    /// grids on a display the same way. Each offset component floors and is
    /// clamped to `>= 0`, so an image already larger than the display (a case
    /// `fit` never produces, but a manually-chosen size might) does not yield
    /// a negative offset.
    nonisolated public static func centeringOffset(
        imageWidth: Int, imageHeight: Int,
        displayWidth: Int, displayHeight: Int
    ) -> (x: Int, y: Int) {
        let x = max(0, (displayWidth - imageWidth) / 2)
        let y = max(0, (displayHeight - imageHeight) / 2)
        return (x: x, y: y)
    }
}
