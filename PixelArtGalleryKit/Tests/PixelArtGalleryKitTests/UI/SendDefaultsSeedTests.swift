import Testing
import Foundation
@testable import PixelArtGalleryKit

/// Tests for ``SendDefaultsSeed/seed(_:)``, the pure decision behind
/// `VariantDetailView.seedSendDefaults()`.
///
/// These lock in the fix for the #0064 review bounce: the display-first
/// centered seed was overwritten on first appearance because
/// `seedSendDefaults()` ran twice (once directly, once via the separate
/// `onChange(of: selectedDisplayID)`) and the first run cleared its "pending
/// centered" flag, so the second run fell back to the display's stored
/// defaults. `SendDefaultsSeed.seed(_:)` fixes this by keeping the pending id
/// set as long as `selectedDisplayID` still matches it — so repeated calls
/// with the same input reapply (not revert) the centered offset — and only
/// clearing it once the selection actually diverges to a different display.
@Suite struct SendDefaultsSeedTests {
    private let displayA = UUID()
    private let displayB = UUID()

    /// A 20x20 variant centered on a 45x35 display: centeringOffset gives
    /// x = (45-20)/2 = 12, y = (35-20)/2 = 7 — distinct from the stored
    /// defaults used below (0, 0) so the two branches are never confusable.
    private func baseInput(pending: UUID?, selected: UUID?) -> SendDefaultsSeed.Input {
        SendDefaultsSeed.Input(
            pendingCenteredDisplayID: pending,
            selectedDisplayID: selected,
            variantWidth: 20,
            variantHeight: 20,
            displayWidth: 45,
            displayHeight: 35,
            displayLayer: 3,
            displayOffsetX: 0,
            displayOffsetY: 0
        )
    }

    // MARK: - Display-first path

    @Test func displayFirstSeedsCenteredForTheMatchingDisplay() {
        let output = SendDefaultsSeed.seed(baseInput(pending: displayA, selected: displayA))

        #expect(output.offsetX == 12)
        #expect(output.offsetY == 7)
        #expect(output.layer == 3)
        // Still pending: a same-appearance reseed for this same display must
        // reapply centered, not revert to stored defaults (see next test).
        #expect(output.pendingCenteredDisplayID == displayA)
    }

    /// The exact double-seed the #0064 review bounce hit: `seedSendDefaults()`
    /// (and hence `seed(_:)`) is called a second time for the *same* pending
    /// display, with the pending id from the first call's output fed back in
    /// (as `VariantDetailView` does). It must stay centered, not fall back to
    /// stored defaults.
    @Test func reseedForTheSameStillPendingDisplayStaysCentered() {
        let firstOutput = SendDefaultsSeed.seed(baseInput(pending: displayA, selected: displayA))
        let secondOutput = SendDefaultsSeed.seed(
            baseInput(pending: firstOutput.pendingCenteredDisplayID, selected: displayA)
        )

        #expect(secondOutput.offsetX == 12)
        #expect(secondOutput.offsetY == 7)
        #expect(secondOutput.pendingCenteredDisplayID == displayA)
    }

    /// A third (or Nth) reseed for the same still-pending display keeps
    /// reapplying centered — the fix isn't a one-time tolerance for exactly
    /// two calls, it's idempotent for any number of repeats.
    @Test func repeatedReseedsForTheSameDisplayRemainCenteredIndefinitely() {
        var pending: UUID? = displayA
        var lastOutput: SendDefaultsSeed.Output?
        for _ in 0..<5 {
            let output = SendDefaultsSeed.seed(baseInput(pending: pending, selected: displayA))
            pending = output.pendingCenteredDisplayID
            lastOutput = output
        }

        #expect(lastOutput?.offsetX == 12)
        #expect(lastOutput?.offsetY == 7)
        #expect(pending == displayA)
    }

    // MARK: - Switching displays

    /// Switching to a *different* display than the pending one must seed that
    /// display's stored defaults, not centered — and must clear the pending
    /// id for good.
    @Test func switchingToADifferentDisplaySeedsStoredDefaultsAndClearsPending() {
        let output = SendDefaultsSeed.seed(baseInput(pending: displayA, selected: displayB))

        #expect(output.offsetX == 0)
        #expect(output.offsetY == 0)
        #expect(output.pendingCenteredDisplayID == nil)
    }

    /// Once cleared, switching *back* to the originally-pending display does
    /// not re-center — a deliberate one-shot-per-session semantic, not a
    /// ordering accident.
    @Test func switchingBackToTheOriginallyPendingDisplayAfterClearingStaysAtStoredDefaults() {
        let afterSwitch = SendDefaultsSeed.seed(baseInput(pending: displayA, selected: displayB))
        let afterSwitchBack = SendDefaultsSeed.seed(
            baseInput(pending: afterSwitch.pendingCenteredDisplayID, selected: displayA)
        )

        #expect(afterSwitchBack.offsetX == 0)
        #expect(afterSwitchBack.offsetY == 0)
        #expect(afterSwitchBack.pendingCenteredDisplayID == nil)
    }

    // MARK: - Variant-list path (no pending id)

    @Test func variantListPathWithNoPendingIDSeedsStoredDefaults() {
        let output = SendDefaultsSeed.seed(baseInput(pending: nil, selected: displayA))

        #expect(output.offsetX == 0)
        #expect(output.offsetY == 0)
        #expect(output.pendingCenteredDisplayID == nil)
    }

    @Test func variantListPathWithNoSelectionSeedsStoredDefaults() {
        let output = SendDefaultsSeed.seed(baseInput(pending: nil, selected: nil))

        #expect(output.offsetX == 0)
        #expect(output.offsetY == 0)
        #expect(output.pendingCenteredDisplayID == nil)
    }

    // MARK: - Clamping

    /// The layer always seeds from the display's stored default, clamped,
    /// regardless of which offset branch is taken.
    @Test func layerClampsFromStoredDefaultInBothBranches() {
        let outOfRangeLayer = SendDefaultsSeed.Input(
            pendingCenteredDisplayID: displayA, selectedDisplayID: displayA,
            variantWidth: 20, variantHeight: 20,
            displayWidth: 45, displayHeight: 35,
            displayLayer: 99, displayOffsetX: 0, displayOffsetY: 0
        )
        #expect(SendDefaultsSeed.seed(outOfRangeLayer).layer == FlaschenTaschenDisplay.layerRange.upperBound)
    }

    /// A stored default that overflows the display given the variant's size
    /// is clamped into `offsetRange`, not applied verbatim.
    @Test func storedDefaultsClampIntoOffsetRange() {
        let overflowing = SendDefaultsSeed.Input(
            pendingCenteredDisplayID: nil, selectedDisplayID: displayA,
            variantWidth: 40, variantHeight: 30,
            displayWidth: 45, displayHeight: 35,
            displayLayer: 3, displayOffsetX: 999, displayOffsetY: 999
        )
        let output = SendDefaultsSeed.seed(overflowing)
        // offsetRange for width: 0...(45-40) = 0...5; for height: 0...(35-30) = 0...5
        #expect(output.offsetX == 5)
        #expect(output.offsetY == 5)
    }

    /// The centered offset itself is also clamped into `offsetRange` — belt
    /// and suspenders, since `AspectFit.centeringOffset` already guarantees
    /// this for well-formed inputs, but the seed function doesn't assume it.
    @Test func centeredOffsetClampsIntoOffsetRange() {
        let tightFit = SendDefaultsSeed.Input(
            pendingCenteredDisplayID: displayA, selectedDisplayID: displayA,
            variantWidth: 44, variantHeight: 34,
            displayWidth: 45, displayHeight: 35,
            displayLayer: 3, displayOffsetX: 0, displayOffsetY: 0
        )
        let output = SendDefaultsSeed.seed(tightFit)
        // centeringOffset: x = (45-44)/2 = 0, y = (35-34)/2 = 0; offsetRange
        // upper bounds are 0...1 on each axis, so 0 is already in range.
        #expect(output.offsetX == 0)
        #expect(output.offsetY == 0)
    }
}
