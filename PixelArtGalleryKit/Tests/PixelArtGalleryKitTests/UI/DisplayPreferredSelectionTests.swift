import Testing
import Foundation
@testable import PixelArtGalleryKit

/// Tests for ``FlaschenTaschenDisplay/preferredSelection(current:lastUsed:variantWidth:variantHeight:among:)``,
/// the pure selection rule behind the variant screen's Send to Display picker.
/// Originally #0032 (prefer the seeded default display, fall back to the
/// first, never stomp a still-valid existing selection); extended by #0055 to
/// auto-select the display whose geometry matches the variant's dimensions
/// before falling back to the #0032 rule; extended by #0079 to break ties
/// among several equal-dimension matches toward the last-used display rather
/// than arbitrary candidate order.
@MainActor
@Suite struct DisplayPreferredSelectionTests {

    private let defaultID = UUID()
    private let manualID = UUID()
    private let mdnsID = UUID()

    /// Candidate list with the default display deliberately not first,
    /// mirroring the picker's name-sorted `@Query`. None of these geometries
    /// match the variant dimensions used in the #0032-style fallback tests,
    /// so they exercise the "nothing matches" fallback path.
    private var candidates: [(id: UUID, source: String, width: Int, height: Int)] {
        [
            (id: manualID, source: "manual", width: 45, height: 35),
            (id: defaultID, source: "default", width: 45, height: 35),
            (id: mdnsID, source: "mdns", width: 45, height: 35)
        ]
    }

    // MARK: - #0032 fallback behavior (no geometry match)

    @Test func prefersDefaultSourceWhenNoCurrentSelection() {
        let selected = FlaschenTaschenDisplay.preferredSelection(
            current: nil,
            variantWidth: 8,
            variantHeight: 8,
            among: candidates
        )
        #expect(selected == defaultID)
    }

    @Test func fallsBackToFirstWhenNoDefaultSource() {
        let noDefault: [(id: UUID, source: String, width: Int, height: Int)] = [
            (id: manualID, source: "manual", width: 45, height: 35),
            (id: mdnsID, source: "mdns", width: 45, height: 35)
        ]
        let selected = FlaschenTaschenDisplay.preferredSelection(
            current: nil,
            variantWidth: 8,
            variantHeight: 8,
            among: noDefault
        )
        #expect(selected == manualID)
    }

    @Test func keepsValidExistingSelectionOverDefault() {
        let selected = FlaschenTaschenDisplay.preferredSelection(
            current: mdnsID,
            variantWidth: 8,
            variantHeight: 8,
            among: candidates
        )
        #expect(selected == mdnsID)
    }

    @Test func replacesStaleSelectionWithDefault() {
        let removedID = UUID()
        let selected = FlaschenTaschenDisplay.preferredSelection(
            current: removedID,
            variantWidth: 8,
            variantHeight: 8,
            among: candidates
        )
        #expect(selected == defaultID)
    }

    @Test func returnsNilWhenNoCandidates() {
        let selected = FlaschenTaschenDisplay.preferredSelection(
            current: manualID,
            variantWidth: 8,
            variantHeight: 8,
            among: []
        )
        #expect(selected == nil)
    }

    // MARK: - #0055 geometry matching

    @Test func autoSelectsSoleMatchingDisplayOverDefault() {
        let eightByEightID = UUID()
        let mixed: [(id: UUID, source: String, width: Int, height: Int)] = [
            (id: defaultID, source: "default", width: 45, height: 35),
            (id: eightByEightID, source: "manual", width: 8, height: 8)
        ]
        let selected = FlaschenTaschenDisplay.preferredSelection(
            current: nil,
            variantWidth: 8,
            variantHeight: 8,
            among: mixed
        )
        #expect(selected == eightByEightID)
    }

    @Test func keepsCurrentSelectionThatAlreadyMatchesAmongSeveralMatches() {
        let firstMatchID = UUID()
        let secondMatchID = UUID()
        let matches: [(id: UUID, source: String, width: Int, height: Int)] = [
            (id: firstMatchID, source: "manual", width: 8, height: 8),
            (id: secondMatchID, source: "mdns", width: 8, height: 8)
        ]
        let selected = FlaschenTaschenDisplay.preferredSelection(
            current: secondMatchID,
            variantWidth: 8,
            variantHeight: 8,
            among: matches
        )
        #expect(selected == secondMatchID)
    }

    @Test func picksFirstMatchInCandidateOrderWhenCurrentDoesNotMatch() {
        let firstMatchID = UUID()
        let secondMatchID = UUID()
        let matches: [(id: UUID, source: String, width: Int, height: Int)] = [
            (id: firstMatchID, source: "manual", width: 8, height: 8),
            (id: secondMatchID, source: "mdns", width: 8, height: 8)
        ]
        let selected = FlaschenTaschenDisplay.preferredSelection(
            current: mdnsID, // not in the match set, and not in candidates at all
            variantWidth: 8,
            variantHeight: 8,
            among: matches
        )
        #expect(selected == firstMatchID)
    }

    @Test func replacesNonMatchingCurrentWithAMatch() {
        let matchID = UUID()
        let nonMatchingCurrentID = UUID()
        let mixed: [(id: UUID, source: String, width: Int, height: Int)] = [
            (id: nonMatchingCurrentID, source: "default", width: 45, height: 35),
            (id: matchID, source: "manual", width: 8, height: 8)
        ]
        let selected = FlaschenTaschenDisplay.preferredSelection(
            current: nonMatchingCurrentID,
            variantWidth: 8,
            variantHeight: 8,
            among: mixed
        )
        #expect(selected == matchID)
    }

    @Test func fallsBackToDefaultFirstOrNilWhenNothingMatches() {
        // Nothing in `candidates` is 8x8, so this exercises the #0032
        // fallback: default source wins.
        let selected = FlaschenTaschenDisplay.preferredSelection(
            current: nil,
            variantWidth: 8,
            variantHeight: 8,
            among: candidates
        )
        #expect(selected == defaultID)
    }

    @Test func returnsNilForEmptyCandidateListEvenWithCurrent() {
        let selected = FlaschenTaschenDisplay.preferredSelection(
            current: manualID,
            variantWidth: 8,
            variantHeight: 8,
            among: []
        )
        #expect(selected == nil)
    }

    // MARK: - #0079 last-used tie-break

    @Test func lastUsedBreaksTieAmongEqualDimensionMatches() {
        let firstMatchID = UUID()
        let secondMatchID = UUID()
        let matches: [(id: UUID, source: String, width: Int, height: Int)] = [
            (id: firstMatchID, source: "manual", width: 45, height: 35),
            (id: secondMatchID, source: "mdns", width: 45, height: 35)
        ]
        let selected = FlaschenTaschenDisplay.preferredSelection(
            current: nil,
            lastUsed: secondMatchID,
            variantWidth: 45,
            variantHeight: 35,
            among: matches
        )
        #expect(selected == secondMatchID)
    }

    @Test func currentMatchingSelectionWinsOverLastUsed() {
        let firstMatchID = UUID()
        let secondMatchID = UUID()
        let matches: [(id: UUID, source: String, width: Int, height: Int)] = [
            (id: firstMatchID, source: "manual", width: 45, height: 35),
            (id: secondMatchID, source: "mdns", width: 45, height: 35)
        ]
        let selected = FlaschenTaschenDisplay.preferredSelection(
            current: firstMatchID,
            lastUsed: secondMatchID,
            variantWidth: 45,
            variantHeight: 35,
            among: matches
        )
        #expect(selected == firstMatchID)
    }

    @Test func lastUsedNotAmongMatchesFallsBackToFirstMatch() {
        let firstMatchID = UUID()
        let secondMatchID = UUID()
        let nonMatchingID = UUID()
        let matches: [(id: UUID, source: String, width: Int, height: Int)] = [
            (id: firstMatchID, source: "manual", width: 45, height: 35),
            (id: secondMatchID, source: "mdns", width: 45, height: 35)
        ]
        let selected = FlaschenTaschenDisplay.preferredSelection(
            current: nil,
            lastUsed: nonMatchingID,
            variantWidth: 45,
            variantHeight: 35,
            among: matches
        )
        #expect(selected == firstMatchID)
    }

    @Test func lastUsedDoesNotAffectNoMatchFallback() {
        // Nothing in `candidates` is 8x8, so this exercises the #0032
        // fallback: default source wins, regardless of `lastUsed`.
        let selected = FlaschenTaschenDisplay.preferredSelection(
            current: nil,
            lastUsed: mdnsID,
            variantWidth: 8,
            variantHeight: 8,
            among: candidates
        )
        #expect(selected == defaultID)
    }

    @Test func singleMatchIgnoresLastUsed() {
        let soleMatchID = UUID()
        let nonMatchingID = UUID()
        let mixed: [(id: UUID, source: String, width: Int, height: Int)] = [
            (id: nonMatchingID, source: "default", width: 45, height: 35),
            (id: soleMatchID, source: "manual", width: 8, height: 8)
        ]
        let selected = FlaschenTaschenDisplay.preferredSelection(
            current: nil,
            lastUsed: nonMatchingID,
            variantWidth: 8,
            variantHeight: 8,
            among: mixed
        )
        #expect(selected == soleMatchID)
    }

    @Test func nilLastUsedKeepsFirstMatchOrder() {
        let firstMatchID = UUID()
        let secondMatchID = UUID()
        let matches: [(id: UUID, source: String, width: Int, height: Int)] = [
            (id: firstMatchID, source: "manual", width: 45, height: 35),
            (id: secondMatchID, source: "mdns", width: 45, height: 35)
        ]
        let selected = FlaschenTaschenDisplay.preferredSelection(
            current: nil,
            lastUsed: nil,
            variantWidth: 45,
            variantHeight: 35,
            among: matches
        )
        #expect(selected == firstMatchID)
    }
}
