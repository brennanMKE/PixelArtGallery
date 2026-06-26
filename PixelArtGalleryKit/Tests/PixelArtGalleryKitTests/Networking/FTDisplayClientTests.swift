import XCTest
@testable import PixelArtGalleryKit

/// Device-free tests for the FT send packet construction.
///
/// The actual UDP transmission in `FTDisplayClient.send` requires a real (or
/// listening) Flaschen Taschen display on the network and cannot be exercised
/// reliably headlessly; these tests cover everything that determines what bytes
/// go on the wire — the P6 PPM header, payload byte count, RGB pixel ordering,
/// and the trailing offset footer.
final class FTDisplayClientTests: XCTestCase {

    /// Build RGBA8888 data for a `width × height` grid from row-major RGBA tuples.
    private func rgbaData(_ pixels: [(UInt8, UInt8, UInt8, UInt8)]) -> Data {
        var bytes = [UInt8]()
        for (r, g, b, a) in pixels {
            bytes.append(contentsOf: [r, g, b, a])
        }
        return Data(bytes)
    }

    // MARK: - Header

    func testPacketStartsWithP6Header() throws {
        let data = rgbaData(Array(repeating: (0, 0, 0, 255), count: 6)) // 3x2
        let packet = try FTDisplayClient.makePacket(
            width: 3, height: 2, pixelGridData: data, scaleFactor: 1.0
        )

        let header = "P6\n3 2\n255\n"
        XCTAssertTrue(packet.starts(with: Array(header.utf8)),
                      "Packet must begin with the P6 PPM header")
    }

    // MARK: - Byte count

    func testPacketByteCountMatchesHeaderPlusRGBPlusFooter() throws {
        // 2x2 grid, all distinct so we can verify ordering too.
        let data = rgbaData([
            (10, 20, 30, 255), (40, 50, 60, 255),
            (70, 80, 90, 255), (100, 110, 120, 255),
        ])
        let packet = try FTDisplayClient.makePacket(
            width: 2, height: 2, pixelGridData: data, scaleFactor: 1.0
        )

        let header = "P6\n2 2\n255\n"
        let headerBytes = header.utf8.count
        let pixelBytes = 2 * 2 * 3 // RGB only, alpha dropped
        // Footer: 0x00 + "0\n0\n0\n"
        let footerBytes = 1 + "0\n0\n0\n".utf8.count

        XCTAssertEqual(packet.count, headerBytes + pixelBytes + footerBytes)
    }

    // MARK: - Pixel ordering (RGB, alpha dropped, row-major)

    func testPixelOrderingIsRowMajorRGB() throws {
        let data = rgbaData([
            (10, 20, 30, 255), (40, 50, 60, 255),
            (70, 80, 90, 255), (100, 110, 120, 255),
        ])
        let packet = try FTDisplayClient.makePacket(
            width: 2, height: 2, pixelGridData: data, scaleFactor: 1.0
        )

        let header = "P6\n2 2\n255\n"
        let headerCount = header.utf8.count
        let pixelRegion = Array(packet[headerCount..<(headerCount + 12)])

        XCTAssertEqual(pixelRegion, [
            10, 20, 30,
            40, 50, 60,
            70, 80, 90,
            100, 110, 120,
        ], "Pixels must be row-major RGB triples with alpha stripped")
    }

    // MARK: - Footer

    func testFooterEncodesOffset() throws {
        let data = rgbaData([(1, 2, 3, 255)]) // 1x1
        let packet = try FTDisplayClient.makePacket(
            width: 1, height: 1, pixelGridData: data, scaleFactor: 1.0,
            offset: (5, 7, 2)
        )

        let footer = Data([0x00]) + Data("5\n7\n2\n".utf8)
        XCTAssertTrue(packet.suffix(footer.count) == footer,
                      "Packet must end with the FT offset footer")
    }

    func testDefaultFooterIsOrigin() throws {
        let data = rgbaData([(1, 2, 3, 255)])
        let packet = try FTDisplayClient.makePacket(
            width: 1, height: 1, pixelGridData: data, scaleFactor: 1.0
        )

        let footer = Data([0x00]) + Data("0\n0\n0\n".utf8)
        XCTAssertTrue(packet.suffix(footer.count) == footer)
    }

    // MARK: - Error handling

    func testMismatchedPixelDataThrows() {
        let data = rgbaData([(0, 0, 0, 255)]) // 1 pixel of data...
        XCTAssertThrowsError(
            try FTDisplayClient.makePacket(
                width: 4, height: 4, pixelGridData: data, scaleFactor: 1.0
            )
        ) { error in
            XCTAssertTrue(error is FTDisplayError,
                          "Encoding failure must surface as FTDisplayError")
        }
    }

    func testInvalidPortRejected() async {
        let client = FTDisplayClient()
        let data = rgbaData([(0, 0, 0, 255)])
        do {
            try await client.send(
                width: 1, height: 1, pixelGridData: data, scaleFactor: 1.0,
                to: "127.0.0.1", port: 0
            )
            XCTFail("Expected invalidPort error")
        } catch let error as FTDisplayError {
            XCTAssertEqual(error, .invalidPort(0))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testEmptyHostRejected() async {
        let client = FTDisplayClient()
        let data = rgbaData([(0, 0, 0, 255)])
        do {
            try await client.send(
                width: 1, height: 1, pixelGridData: data, scaleFactor: 1.0,
                to: "   ", port: 1337
            )
            XCTFail("Expected invalidHost error")
        } catch let error as FTDisplayError {
            XCTAssertEqual(error, .invalidHost("   "))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
