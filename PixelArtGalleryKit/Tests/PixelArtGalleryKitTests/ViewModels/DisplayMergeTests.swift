import Testing
import SwiftData
@testable import PixelArtGalleryKit

/// Device-free tests for merging mDNS-discovered displays into the persisted
/// registry, de-duplicated by host+port.
///
/// Two layers are exercised: the pure ``DisplayMergePlan`` decision logic, and
/// the coordinator's ``GalleryCoordinator/mergeDiscoveredDisplays(_:)`` applied
/// over an in-memory `ModelContext`. The live `NWBrowser`/mDNS path in
/// `FTDiscoveryService` requires a real network with an FT display advertising
/// and cannot be exercised headlessly — only the merge that follows discovery is
/// covered here.
@MainActor
@Suite struct DisplayMergeTests {

    /// A fresh in-memory SwiftData context for the registry model.
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: FlaschenTaschenDisplay.self, configurations: config)
        return ModelContext(container)
    }

    private func discovered(
        host: String,
        port: Int = 1337,
        name: String = "FT",
        width: Int? = nil,
        height: Int? = nil
    ) -> DiscoveredFTDisplay {
        DiscoveredFTDisplay(
            host: host, port: port, serviceName: name,
            displayWidth: width, displayHeight: height
        )
    }

    // MARK: - Pure plan logic

    @Test func planInsertsAllWhenRegistryEmpty() {
        let plan = DisplayMergePlan.build(
            existing: [],
            discovered: [discovered(host: "a.local"), discovered(host: "b.local")]
        )
        #expect(plan.insertions.count == 2)
        #expect(plan.updates.count == 0)
    }

    @Test func planCollapsesDuplicateDiscoveriesByEndpoint() {
        let plan = DisplayMergePlan.build(
            existing: [],
            discovered: [
                discovered(host: "a.local", name: "first"),
                discovered(host: "A.LOCAL", name: "second"), // same endpoint, different case
            ]
        )
        #expect(plan.insertions.count == 1)
        #expect(plan.insertions.first?.serviceName == "second") // last wins
    }

    @Test func keyIsCaseInsensitiveAndPortSensitive() {
        #expect(
            DisplayMergePlan.key(host: "FT.local", port: 1337) ==
            DisplayMergePlan.key(host: "ft.local", port: 1337)
        )
        #expect(
            DisplayMergePlan.key(host: "ft.local", port: 1337) !=
            DisplayMergePlan.key(host: "ft.local", port: 1338)
        )
    }

    // MARK: - Applied merge over a ModelContext

    @Test func mergeInsertsNewDisplaysAsMdns() throws {
        let context = try makeContext()
        let coordinator = GalleryCoordinator()
        coordinator.configure(modelContext: context)

        let result = coordinator.mergeDiscoveredDisplays([
            discovered(host: "10.0.0.1", name: "Office", width: 64, height: 32),
        ])

        #expect(result.inserted == 1)
        #expect(result.updated == 0)

        let stored = try context.fetch(FetchDescriptor<FlaschenTaschenDisplay>())
        #expect(stored.count == 1)
        #expect(stored.first?.source == "mdns")
        #expect(stored.first?.displayWidth == 64)
        #expect(stored.first?.displayHeight == 32)
    }

    @Test func mergeDeDupesAgainstExistingByHostAndPort() throws {
        let context = try makeContext()
        let coordinator = GalleryCoordinator()
        coordinator.configure(modelContext: context)

        // Seed an existing (manual) display.
        let existing = FlaschenTaschenDisplay(
            host: "10.0.0.1", port: 1337, displayName: "Old Name",
            displayWidth: 16, displayHeight: 16, source: "manual"
        )
        context.insert(existing)
        try context.save()

        // Discover the same endpoint with refreshed metadata.
        let result = coordinator.mergeDiscoveredDisplays([
            discovered(host: "10.0.0.1", name: "New Name", width: 64, height: 64),
        ])

        #expect(result.inserted == 0)
        #expect(result.updated == 1)

        let stored = try context.fetch(FetchDescriptor<FlaschenTaschenDisplay>())
        #expect(stored.count == 1, "Should update in place, not duplicate")
        #expect(stored.first?.displayName == "New Name")
        #expect(stored.first?.displayWidth == 64)
        #expect(stored.first?.displayHeight == 64)
        #expect(stored.first?.source == "mdns")
    }

    @Test func mergeHandlesMixedInsertAndUpdate() throws {
        let context = try makeContext()
        let coordinator = GalleryCoordinator()
        coordinator.configure(modelContext: context)

        let existing = FlaschenTaschenDisplay(
            host: "10.0.0.1", port: 1337, displayName: "Existing",
            displayWidth: 16, displayHeight: 16, source: "manual"
        )
        context.insert(existing)
        try context.save()

        let result = coordinator.mergeDiscoveredDisplays([
            discovered(host: "10.0.0.1", name: "Existing Updated", width: 32, height: 32),
            discovered(host: "10.0.0.2", name: "Brand New", width: 45, height: 35),
        ])

        #expect(result.inserted == 1)
        #expect(result.updated == 1)

        let stored = try context.fetch(FetchDescriptor<FlaschenTaschenDisplay>())
        #expect(stored.count == 2)
    }

    @Test func mergeWithEmptyDiscoveryIsNoOp() throws {
        let context = try makeContext()
        let coordinator = GalleryCoordinator()
        coordinator.configure(modelContext: context)

        let result = coordinator.mergeDiscoveredDisplays([])
        #expect(result.inserted == 0)
        #expect(result.updated == 0)
    }

    @Test func mergeWithoutContextReturnsZero() {
        let coordinator = GalleryCoordinator()
        let result = coordinator.mergeDiscoveredDisplays([discovered(host: "x")])
        #expect(result.inserted == 0)
        #expect(result.updated == 0)
    }

    // MARK: - Rename / delete

    @Test func renameDisplayPersists() throws {
        let context = try makeContext()
        let coordinator = GalleryCoordinator()
        coordinator.configure(modelContext: context)

        let display = FlaschenTaschenDisplay(
            host: "10.0.0.1", port: 1337, displayName: "Before",
            displayWidth: 16, displayHeight: 16
        )
        context.insert(display)
        try context.save()

        coordinator.renameDisplay(display, to: "  After  ")
        #expect(display.displayName == "After", "Name is trimmed and saved")

        coordinator.renameDisplay(display, to: "   ")
        #expect(display.displayName == "After", "Empty rename is rejected")
    }

    @Test func deleteDisplayRemovesIt() throws {
        let context = try makeContext()
        let coordinator = GalleryCoordinator()
        coordinator.configure(modelContext: context)

        let display = FlaschenTaschenDisplay(
            host: "10.0.0.1", port: 1337, displayName: "Doomed",
            displayWidth: 16, displayHeight: 16
        )
        context.insert(display)
        try context.save()

        coordinator.deleteDisplay(display)

        let stored = try context.fetch(FetchDescriptor<FlaschenTaschenDisplay>())
        #expect(stored.isEmpty)
    }

    // MARK: - Editing in place (#0054)

    @Test func updateDisplayPersistsAllFieldsIncludingLayer() throws {
        let context = try makeContext()
        let coordinator = GalleryCoordinator()
        coordinator.configure(modelContext: context)

        let display = FlaschenTaschenDisplay(
            host: "10.0.0.1", port: 1337, displayName: "Before",
            displayWidth: 16, displayHeight: 16, source: "manual", layer: 3
        )
        context.insert(display)
        try context.save()

        let validated = ManualDisplayInput.Validated(
            host: "10.0.0.2", port: 1338, displayName: "After", width: 32, height: 24
        )
        try coordinator.updateDisplay(display, with: validated, layer: 9)

        #expect(display.host == "10.0.0.2")
        #expect(display.port == 1338)
        #expect(display.displayName == "After")
        #expect(display.displayWidth == 32)
        #expect(display.displayHeight == 24)
        #expect(display.layer == 9)

        // Re-fetch to confirm the edit was actually saved, not just mutated
        // on the in-memory object.
        let refetched = try #require(try context.fetch(FetchDescriptor<FlaschenTaschenDisplay>()).first)
        #expect(refetched.host == "10.0.0.2")
        #expect(refetched.layer == 9)
    }

    @Test func updateDisplayClampsOutOfRangeLayer() throws {
        let context = try makeContext()
        let coordinator = GalleryCoordinator()
        coordinator.configure(modelContext: context)

        let display = FlaschenTaschenDisplay(
            host: "10.0.0.1", port: 1337, displayName: "Before",
            displayWidth: 16, displayHeight: 16
        )
        context.insert(display)
        try context.save()

        let validated = ManualDisplayInput.Validated(
            host: "10.0.0.1", port: 1337, displayName: "Before", width: 16, height: 16
        )
        try coordinator.updateDisplay(display, with: validated, layer: 99)
        #expect(display.layer == FlaschenTaschenDisplay.layerRange.upperBound,
                "Layer must be clamped into the valid range, never stored out of bounds")

        try coordinator.updateDisplay(display, with: validated, layer: -5)
        #expect(display.layer == FlaschenTaschenDisplay.layerRange.lowerBound)
    }

    @Test func updateDisplayWithoutContextThrows() {
        let coordinator = GalleryCoordinator()
        let display = FlaschenTaschenDisplay(
            host: "10.0.0.1", port: 1337, displayName: "Orphan",
            displayWidth: 16, displayHeight: 16
        )
        let validated = ManualDisplayInput.Validated(
            host: "10.0.0.1", port: 1337, displayName: "Orphan", width: 16, height: 16
        )
        #expect(throws: GalleryCoordinatorError.missingModelContext) {
            try coordinator.updateDisplay(display, with: validated, layer: 5)
        }
    }

    // MARK: - Restoring the default (#0054)

    @Test func restoreDefaultDisplayInsertsBuiltInDisplay() throws {
        let context = try makeContext()
        let coordinator = GalleryCoordinator()
        coordinator.configure(modelContext: context)

        // Seed a manual display first, mirroring the scenario where a user
        // deleted the default while keeping others.
        let manual = FlaschenTaschenDisplay(
            host: "10.0.0.5", port: 1337, displayName: "Office",
            displayWidth: 64, displayHeight: 32, source: "manual"
        )
        context.insert(manual)
        try context.save()

        let restored = coordinator.restoreDefaultDisplay()
        #expect(restored?.source == FlaschenTaschenDisplay.defaultSource)

        let stored = try context.fetch(FetchDescriptor<FlaschenTaschenDisplay>())
        #expect(stored.count == 2, "Restoring the default must not remove the other display")
        #expect(stored.contains { $0.source == FlaschenTaschenDisplay.defaultSource })
    }

    @Test func restoreDefaultDisplayWithoutContextReturnsNil() {
        let coordinator = GalleryCoordinator()
        #expect(coordinator.restoreDefaultDisplay() == nil)
    }
}
