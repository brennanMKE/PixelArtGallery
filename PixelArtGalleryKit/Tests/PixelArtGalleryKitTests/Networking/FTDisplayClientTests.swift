import Testing
import Foundation
@testable import PixelArtGalleryKit

/// Device-free tests for the FT send packet construction.
///
/// The actual UDP transmission in `FTDisplayClient.send` requires a real (or
/// listening) Flaschen Taschen display and cannot be exercised reliably
/// headlessly; these tests cover everything that determines what bytes go on the
/// wire — the P6 PPM header, the `#FT:` offset/layer comment, payload byte count,
/// and RGB pixel ordering.
@Suite struct FTDisplayClientTests {

    /// Build RGBA8888 data for a `width × height` grid from row-major RGBA tuples.
    private func rgbaData(_ pixels: [(UInt8, UInt8, UInt8, UInt8)]) -> Data {
        var bytes = [UInt8]()
        for (r, g, b, a) in pixels {
            bytes.append(contentsOf: [r, g, b, a])
        }
        return Data(bytes)
    }

    /// The full ASCII header the packet must start with, including the injected
    /// `#FT:` offset/layer comment between the dimensions line and the maxval.
    private func expectedHeader(width: Int, height: Int, offset: (Int, Int, Int)) -> String {
        "P6\n\(width) \(height)\n#FT: \(offset.0) \(offset.1) \(offset.2)\n255\n"
    }

    // MARK: - Header

    @Test func packetStartsWithP6HeaderIncludingFTComment() throws {
        let data = rgbaData(Array(repeating: (0, 0, 0, 255), count: 6)) // 3x2
        let packet = try FTDisplayClient.makePacket(
            width: 3, height: 2, pixelGridData: data, scaleFactor: 1.0
        )

        let header = expectedHeader(width: 3, height: 2, offset: (0, 0, 0))
        #expect(packet.starts(with: Array(header.utf8)),
                "Packet must begin with the P6 header carrying the #FT: comment")
    }

    // MARK: - #FT: offset / layer comment (regression for #0051)

    @Test func ftCommentEncodesOffsetAndLayer() throws {
        let data = rgbaData([(1, 2, 3, 255)]) // 1x1
        let packet = try FTDisplayClient.makePacket(
            width: 1, height: 1, pixelGridData: data, scaleFactor: 1.0,
            offset: (5, 7, 2)
        )

        // The layer/offset must ride in the header as `#FT: 5 7 2`, the exact form
        // the FT server parses. The reference client uses this comment; the old
        // trailing `0x00`-prefixed footer made the server drop the layer.
        let header = expectedHeader(width: 1, height: 1, offset: (5, 7, 2))
        #expect(packet.starts(with: Array(header.utf8)),
                "The #FT: comment must encode x, y and layer in the header")
    }

    @Test func defaultOffsetIsOrigin() throws {
        let data = rgbaData([(1, 2, 3, 255)])
        let packet = try FTDisplayClient.makePacket(
            width: 1, height: 1, pixelGridData: data, scaleFactor: 1.0
        )

        let header = expectedHeader(width: 1, height: 1, offset: (0, 0, 0))
        #expect(packet.starts(with: Array(header.utf8)))
    }

    /// The bug in #0051: a leading `0x00` byte before the offsets made the server's
    /// number parser bail and default the layer to 0. The packet must not carry
    /// that NUL byte anywhere.
    @Test func packetContainsNoNulByte() throws {
        let data = rgbaData([(1, 2, 3, 255)])
        let packet = try FTDisplayClient.makePacket(
            width: 1, height: 1, pixelGridData: data, scaleFactor: 1.0,
            offset: (0, 0, 5)
        )
        #expect(!packet.contains(0x00), "A 0x00 byte makes the FT server ignore the offset/layer")
    }

    // MARK: - Byte count

    @Test func packetByteCountMatchesHeaderPlusRGB() throws {
        let data = rgbaData([
            (10, 20, 30, 255), (40, 50, 60, 255),
            (70, 80, 90, 255), (100, 110, 120, 255),
        ])
        let packet = try FTDisplayClient.makePacket(
            width: 2, height: 2, pixelGridData: data, scaleFactor: 1.0,
            offset: (1, 2, 3)
        )

        let headerBytes = expectedHeader(width: 2, height: 2, offset: (1, 2, 3)).utf8.count
        let pixelBytes = 2 * 2 * 3 // RGB only, alpha dropped
        #expect(packet.count == headerBytes + pixelBytes)
    }

    // MARK: - Pixel ordering (RGB, alpha dropped, row-major)

    @Test func pixelOrderingIsRowMajorRGB() throws {
        let data = rgbaData([
            (10, 20, 30, 255), (40, 50, 60, 255),
            (70, 80, 90, 255), (100, 110, 120, 255),
        ])
        let packet = try FTDisplayClient.makePacket(
            width: 2, height: 2, pixelGridData: data, scaleFactor: 1.0
        )

        let headerCount = expectedHeader(width: 2, height: 2, offset: (0, 0, 0)).utf8.count
        let pixelRegion = Array(packet[headerCount..<(headerCount + 12)])

        #expect(pixelRegion == [
            10, 20, 30,
            40, 50, 60,
            70, 80, 90,
            100, 110, 120,
        ], "Pixels must be row-major RGB triples with alpha stripped")
    }

    // MARK: - Layer clear frame (#0053)

    /// The layer-clear frame is all-zero RGBA pixel data. Its packet must carry
    /// black (0,0,0) RGB for every pixel on the chosen layer — the FT server
    /// composites black on layers 1–15 as transparent, erasing the overlay.
    @Test func allBlackFrameProducesBlackPixelsOnChosenLayer() throws {
        let width = 2, height = 2
        let blackFrame = Data(count: width * height * 4) // all zero → black
        let packet = try FTDisplayClient.makePacket(
            width: width, height: height, pixelGridData: blackFrame, scaleFactor: 1.0,
            offset: (0, 0, 5)
        )

        let header = expectedHeader(width: width, height: height, offset: (0, 0, 5))
        #expect(packet.starts(with: Array(header.utf8)), "Clear frame must target the chosen layer via #FT:")

        let pixels = Array(packet.dropFirst(header.utf8.count))
        #expect(pixels.count == width * height * 3, "RGB pixel region should follow the header")
        #expect(pixels.allSatisfy { $0 == 0 }, "Every pixel of the clear frame must be black (0,0,0)")
    }

    // MARK: - Error handling

    @Test func mismatchedPixelDataThrows() {
        let data = rgbaData([(0, 0, 0, 255)]) // 1 pixel of data...
        #expect(throws: FTDisplayError.self) {
            try FTDisplayClient.makePacket(
                width: 4, height: 4, pixelGridData: data, scaleFactor: 1.0
            )
        }
    }

    @Test func invalidPortRejected() async {
        let client = FTDisplayClient()
        let data = rgbaData([(0, 0, 0, 255)])
        await #expect(throws: FTDisplayError.invalidPort(0)) {
            try await client.send(
                width: 1, height: 1, pixelGridData: data, scaleFactor: 1.0,
                to: "127.0.0.1", port: 0
            )
        }
    }

    @Test func emptyHostRejected() async {
        let client = FTDisplayClient()
        let data = rgbaData([(0, 0, 0, 255)])
        await #expect(throws: FTDisplayError.invalidHost("   ")) {
            try await client.send(
                width: 1, height: 1, pixelGridData: data, scaleFactor: 1.0,
                to: "   ", port: 1337
            )
        }
    }
}
