import Foundation
import XCTest
@testable import PixelArtGalleryKit

/// Tests for ``FlaschenTaschenDisplay/preferredSelection(current:among:)``,
/// the pure selection rule behind the variant screen's Send to Display picker
/// (#0032): prefer the seeded default display, fall back to the first, and
/// never stomp a still-valid existing selection.
@MainActor
final class DisplayPreferredSelectionTests: XCTestCase {

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

    func testPrefersDefaultSourceWhenNoCurrentSelection() {
        let selected = FlaschenTaschenDisplay.preferredSelection(current: nil, among: candidates)
        XCTAssertEqual(selected, defaultID)
    }

    func testFallsBackToFirstWhenNoDefaultSource() {
        let noDefault: [(id: UUID, source: String)] = [
            (id: manualID, source: "manual"),
            (id: mdnsID, source: "mdns")
        ]
        let selected = FlaschenTaschenDisplay.preferredSelection(current: nil, among: noDefault)
        XCTAssertEqual(selected, manualID)
    }

    func testKeepsValidExistingSelectionOverDefault() {
        let selected = FlaschenTaschenDisplay.preferredSelection(current: mdnsID, among: candidates)
        XCTAssertEqual(selected, mdnsID)
    }

    func testReplacesStaleSelectionWithDefault() {
        let removedID = UUID()
        let selected = FlaschenTaschenDisplay.preferredSelection(current: removedID, among: candidates)
        XCTAssertEqual(selected, defaultID)
    }

    func testReturnsNilWhenNoCandidates() {
        let selected = FlaschenTaschenDisplay.preferredSelection(current: manualID, among: [])
        XCTAssertNil(selected)
    }
}
