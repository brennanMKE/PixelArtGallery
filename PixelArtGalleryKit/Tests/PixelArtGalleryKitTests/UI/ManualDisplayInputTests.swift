import XCTest
@testable import PixelArtGalleryKit

final class ManualDisplayInputTests: XCTestCase {
    private func makeInput(
        host: String = "192.168.1.50",
        port: String = "1337",
        displayName: String = "Office Wall",
        width: String = "64",
        height: String = "32"
    ) -> ManualDisplayInput {
        ManualDisplayInput(host: host, port: port, displayName: displayName, width: width, height: height)
    }

    func testValidInputProducesValidatedValues() {
        let result = makeInput().validate()
        guard case .success(let validated) = result else {
            return XCTFail("expected success, got \(result)")
        }
        XCTAssertEqual(validated.host, "192.168.1.50")
        XCTAssertEqual(validated.port, 1337)
        XCTAssertEqual(validated.displayName, "Office Wall")
        XCTAssertEqual(validated.width, 64)
        XCTAssertEqual(validated.height, 32)
        XCTAssertTrue(makeInput().isValid)
    }

    func testHostIsTrimmedAndEmptyHostFails() {
        // Whitespace is trimmed for a real host.
        guard case .success(let validated) = makeInput(host: "  10.0.0.2  ").validate() else {
            return XCTFail("expected trimmed host to validate")
        }
        XCTAssertEqual(validated.host, "10.0.0.2")

        // Empty / whitespace-only host fails.
        XCTAssertEqual(makeInput(host: "").validate(), .failure(.emptyHost))
        XCTAssertEqual(makeInput(host: "   ").validate(), .failure(.emptyHost))
        XCTAssertFalse(makeInput(host: "").isValid)
    }

    func testEmptyDisplayNameFallsBackToHost() {
        guard case .success(let validated) = makeInput(displayName: "   ").validate() else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(validated.displayName, "192.168.1.50")
    }

    func testPortBounds() {
        XCTAssertEqual(makeInput(port: "0").validate(), .failure(.invalidPort))
        XCTAssertEqual(makeInput(port: "65536").validate(), .failure(.invalidPort))
        XCTAssertEqual(makeInput(port: "-1").validate(), .failure(.invalidPort))
        XCTAssertEqual(makeInput(port: "abc").validate(), .failure(.invalidPort))
        XCTAssertEqual(makeInput(port: "").validate(), .failure(.invalidPort))

        // Boundary values are accepted.
        if case .failure = makeInput(port: "1").validate() { XCTFail("port 1 should be valid") }
        if case .failure = makeInput(port: "65535").validate() { XCTFail("port 65535 should be valid") }
    }

    func testDimensionParsing() {
        XCTAssertEqual(makeInput(width: "0").validate(), .failure(.invalidWidth))
        XCTAssertEqual(makeInput(width: "-5").validate(), .failure(.invalidWidth))
        XCTAssertEqual(makeInput(width: "x").validate(), .failure(.invalidWidth))
        XCTAssertEqual(makeInput(height: "0").validate(), .failure(.invalidHeight))
        XCTAssertEqual(makeInput(height: "").validate(), .failure(.invalidHeight))

        guard case .success(let validated) = makeInput(width: " 128 ", height: "96").validate() else {
            return XCTFail("expected success for valid dimensions")
        }
        XCTAssertEqual(validated.width, 128)
        XCTAssertEqual(validated.height, 96)
    }

    func testValidationPriorityHostBeforePort() {
        // Host check runs before port check.
        XCTAssertEqual(makeInput(host: "", port: "0").validate(), .failure(.emptyHost))
    }
}
