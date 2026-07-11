import Foundation

/// Pure decision logic behind `VariantDetailView.seedSendDefaults()`, extracted
/// so it is unit-testable without a live SwiftUI view.
///
/// **Why this exists (#0064 review bounce).** The display-first path seeds the
/// send offsets to the aspect-fit *centered* value for the display the user
/// just picked, instead of that display's *stored* defaults. On first
/// appearance, SwiftUI fires the seeding logic **twice** for the same
/// `nil -> UUID` change of `selectedDisplayID`: once directly from the
/// `displays`-list `onChange` (which also calls `updateSelectedDisplay()`),
/// and again from the separate, pre-existing `onChange(of: selectedDisplayID)`.
/// The prior implementation cleared its "pending centered" flag the first time
/// it applied the centered offset, so the second, redundant call found the
/// flag already cleared and overwrote the offsets with the display's stored
/// defaults — silently discarding the centered seed.
///
/// The fix here does not try to prevent the double call (fragile — depends on
/// SwiftUI's `onChange` firing order, which isn't a stable contract). Instead,
/// `seed(_:)` is **idempotent under repetition**: as long as
/// `selectedDisplayID` still equals `pendingCenteredDisplayID`, every call
/// (however many) recomputes and reapplies the centered offset, and reports
/// the pending id unchanged (still pending). The pending id is only cleared
/// once the *selection itself* diverges from it — i.e. the user (or
/// `updateSelectedDisplay()`) moves to a genuinely different display — at
/// which point seeding falls back to that display's stored defaults and stays
/// there permanently for this view instance (switching back to the
/// originally-pending display later reseeds its stored defaults too, not
/// centered again — a deliberate one-shot-per-session semantic, not an
/// accidental one).
/// Marked `nonisolated` (and its nested types too) because `Package.swift`
/// default-isolates the main target to `MainActor` — a pure helper consumed
/// from nonisolated tests must opt out explicitly rather than rely on that
/// default propagating (this bit `AspectFit` in #0057/#0060, and would bite
/// this type's tests the same way).
nonisolated enum SendDefaultsSeed {
    /// Everything the seeding decision needs, read once per call from the
    /// view's current state.
    nonisolated struct Input: Equatable {
        /// The display a display-first push (#0064) wants the offset centered
        /// on, or `nil` for the ordinary variant-list entry point.
        let pendingCenteredDisplayID: UUID?
        /// The display currently selected in the Send section's picker.
        let selectedDisplayID: UUID?
        let variantWidth: Int
        let variantHeight: Int
        let displayWidth: Int
        let displayHeight: Int
        /// The selected display's stored default paint layer (unclamped).
        let displayLayer: Int
        /// The selected display's stored default offsets (unclamped).
        let displayOffsetX: Int
        let displayOffsetY: Int
    }

    /// The seeded state to apply, plus the pending-centered id to carry
    /// forward (the caller should store this back into its own
    /// `pendingCenteredDisplayID` state).
    nonisolated struct Output: Equatable {
        let layer: Int
        let offsetX: Int
        let offsetY: Int
        let pendingCenteredDisplayID: UUID?
    }

    /// Compute the layer/offset seed for the currently selected display.
    ///
    /// - When `input.pendingCenteredDisplayID` is non-nil and equals
    ///   `input.selectedDisplayID`, the offsets are seeded to the aspect-fit
    ///   centering offset for the variant on that display, and the returned
    ///   `pendingCenteredDisplayID` is the *same* id — still pending, so a
    ///   same-appearance reseed for this display reapplies (not reverts) the
    ///   centered value.
    /// - Otherwise (no pending id, or the selection has moved to a different
    ///   display), the offsets are seeded from the display's stored defaults,
    ///   and the returned `pendingCenteredDisplayID` is `nil` — cleared for
    ///   good, so a later return to the originally-pending display does not
    ///   re-center.
    /// - The layer always seeds from the display's stored default, clamped,
    ///   in both branches.
    /// - Offsets are always clamped into
    ///   ``FlaschenTaschenDisplay/offsetRange(displayDimension:imageDimension:)``
    ///   for the corresponding axis, so neither branch can leave a stepper
    ///   showing an out-of-range value.
    nonisolated static func seed(_ input: Input) -> Output {
        let layer = FlaschenTaschenDisplay.clampedLayer(input.displayLayer)
        let offsetXRange = FlaschenTaschenDisplay.offsetRange(
            displayDimension: input.displayWidth, imageDimension: input.variantWidth
        )
        let offsetYRange = FlaschenTaschenDisplay.offsetRange(
            displayDimension: input.displayHeight, imageDimension: input.variantHeight
        )

        if let pending = input.pendingCenteredDisplayID, pending == input.selectedDisplayID {
            let centered = AspectFit.centeringOffset(
                imageWidth: input.variantWidth, imageHeight: input.variantHeight,
                displayWidth: input.displayWidth, displayHeight: input.displayHeight
            )
            return Output(
                layer: layer,
                offsetX: min(centered.x, offsetXRange.upperBound),
                offsetY: min(centered.y, offsetYRange.upperBound),
                pendingCenteredDisplayID: pending
            )
        }

        return Output(
            layer: layer,
            offsetX: min(FlaschenTaschenDisplay.clampedOffset(input.displayOffsetX), offsetXRange.upperBound),
            offsetY: min(FlaschenTaschenDisplay.clampedOffset(input.displayOffsetY), offsetYRange.upperBound),
            pendingCenteredDisplayID: nil
        )
    }
}
