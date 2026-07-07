import Testing
import Foundation
@testable import PixelArtGalleryKit

/// Tests for ``FlaschenTaschenDisplay/preferredSelection(current:among:)``,
/// the pure selection rule behind the variant screen's Send to Display picker
/// (#0032): prefer the seeded default display, fall back to the first, and
/// never stomp a still-valid existing selection.
@MainActor
@Suite struct DisplayPreferredSelectionTests {

    private let defaultID = UUID()
    private let manualID = UUID()
    private let mdnsID = UUID()

    /// Candidate list with the default display deliberately not first,
    /// mirroring the picker's name-sorted `@Query`.
    private var candidates: [(id: UUID, source: String)] {
        [
            (id: manualID, source: "manual"),
            (id: defaultID, source: "default"),
            (id: mdnsID, source: "mdns")
        ]
    }

    @Test func prefersDefaultSourceWhenNoCurrentSelection() {
        let selected = FlaschenTaschenDisplay.preferredSelection(current: nil, among: candidates)
        #expect(selected == defaultID)
    }

    @Test func fallsBackToFirstWhenNoDefaultSource() {
        let noDefault: [(id: UUID, source: String)] = [
            (id: manualID, source: "manual"),
            (id: mdnsID, source: "mdns")
        ]
        let selected = FlaschenTaschenDisplay.preferredSelection(current: nil, among: noDefault)
        #expect(selected == manualID)
    }

    @Test func keepsValidExistingSelectionOverDefault() {
        let selected = FlaschenTaschenDisplay.preferredSelection(current: mdnsID, among: candidates)
        #expect(selected == mdnsID)
    }

    @Test func replacesStaleSelectionWithDefault() {
        let removedID = UUID()
        let selected = FlaschenTaschenDisplay.preferredSelection(current: removedID, among: candidates)
        #expect(selected == defaultID)
    }

    @Test func returnsNilWhenNoCandidates() {
        let selected = FlaschenTaschenDisplay.preferredSelection(current: manualID, among: [])
        #expect(selected == nil)
    }
}
