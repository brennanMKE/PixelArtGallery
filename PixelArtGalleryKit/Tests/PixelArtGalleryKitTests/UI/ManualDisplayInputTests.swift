import Testing
@testable import PixelArtGalleryKit

@Suite struct ManualDisplayInputTests {
    private func makeInput(
        host: String = "192.168.1.50",
        port: String = "1337",
        displayName: String = "Office Wall",
        width: String = "64",
        height: String = "32",
        offsetX: String = "0",
        offsetY: String = "0"
    ) -> ManualDisplayInput {
        ManualDisplayInput(
            host: host, port: port, displayName: displayName, width: width, height: height,
            offsetX: offsetX, offsetY: offsetY
        )
    }

    @Test func validInputProducesValidatedValues() throws {
        let result = makeInput().validate()
        guard case .success(let validated) = result else {
            Issue.record("expected success, got \(result)")
            return
        }
        #expect(validated.host == "192.168.1.50")
        #expect(validated.port == 1337)
        #expect(validated.displayName == "Office Wall")
        #expect(validated.width == 64)
        #expect(validated.height == 32)
        #expect(validated.offsetX == 0)
        #expect(validated.offsetY == 0)
        #expect(makeInput().isValid)
    }

    // MARK: - Offset validation (#0056)

    @Test func offsetParsing() {
        #expect(makeInput(offsetX: "-1").validate() == .failure(.invalidOffsetX))
        #expect(makeInput(offsetX: "x").validate() == .failure(.invalidOffsetX))
        #expect(makeInput(offsetX: "").validate() == .failure(.invalidOffsetX))
        #expect(makeInput(offsetY: "-1").validate() == .failure(.invalidOffsetY))
        #expect(makeInput(offsetY: "x").validate() == .failure(.invalidOffsetY))
        #expect(makeInput(offsetY: "").validate() == .failure(.invalidOffsetY))

        // Zero is a valid (default) offset.
        if case .failure = makeInput(offsetX: "0", offsetY: "0").validate() {
            Issue.record("zero offsets should be valid")
        }

        guard case .success(let validated) = makeInput(offsetX: " 10 ", offsetY: "20").validate() else {
            Issue.record("expected success for valid positive offsets")
            return
        }
        #expect(validated.offsetX == 10)
        #expect(validated.offsetY == 20)
    }

    @Test func validationPriorityDimensionsBeforeOffsets() {
        // Width/height checks run before offset checks.
        #expect(makeInput(width: "0", offsetX: "-1").validate() == .failure(.invalidWidth))
    }

    @Test func hostIsTrimmedAndEmptyHostFails() {
        // Whitespace is trimmed for a real host.
        guard case .success(let validated) = makeInput(host: "  10.0.0.2  ").validate() else {
            Issue.record("expected trimmed host to validate")
            return
        }
        #expect(validated.host == "10.0.0.2")

        // Empty / whitespace-only host fails.
        #expect(makeInput(host: "").validate() == .failure(.emptyHost))
        #expect(makeInput(host: "   ").validate() == .failure(.emptyHost))
        #expect(!makeInput(host: "").isValid)
    }

    @Test func emptyDisplayNameFallsBackToHost() {
        guard case .success(let validated) = makeInput(displayName: "   ").validate() else {
            Issue.record("expected success")
            return
        }
        #expect(validated.displayName == "192.168.1.50")
    }

    @Test func portBounds() {
        #expect(makeInput(port: "0").validate() == .failure(.invalidPort))
        #expect(makeInput(port: "65536").validate() == .failure(.invalidPort))
        #expect(makeInput(port: "-1").validate() == .failure(.invalidPort))
        #expect(makeInput(port: "abc").validate() == .failure(.invalidPort))
        #expect(makeInput(port: "").validate() == .failure(.invalidPort))

        // Boundary values are accepted.
        if case .failure = makeInput(port: "1").validate() { Issue.record("port 1 should be valid") }
        if case .failure = makeInput(port: "65535").validate() { Issue.record("port 65535 should be valid") }
    }

    @Test func dimensionParsing() {
        #expect(makeInput(width: "0").validate() == .failure(.invalidWidth))
        #expect(makeInput(width: "-5").validate() == .failure(.invalidWidth))
        #expect(makeInput(width: "x").validate() == .failure(.invalidWidth))
        #expect(makeInput(height: "0").validate() == .failure(.invalidHeight))
        #expect(makeInput(height: "").validate() == .failure(.invalidHeight))

        guard case .success(let validated) = makeInput(width: " 128 ", height: "96").validate() else {
            Issue.record("expected success for valid dimensions")
            return
        }
        #expect(validated.width == 128)
        #expect(validated.height == 96)
    }

    @Test func validationPriorityHostBeforePort() {
        // Host check runs before port check.
        #expect(makeInput(host: "", port: "0").validate() == .failure(.emptyHost))
    }
}
