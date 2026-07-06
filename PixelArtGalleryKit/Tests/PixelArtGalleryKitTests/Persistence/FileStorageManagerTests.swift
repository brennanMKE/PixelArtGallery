import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import PixelArtGalleryKit

final class FileStorageManagerTests: XCTestCase {
    var manager: FileStorageManager?

    /// Unique per-test temporary directory the manager stores files in, so the
    /// suite never touches the real `Application Support/PixelArtGallery/Images`
    /// directory the app uses (#0034). Created in `setUp`, removed in `tearDown`.
    private var tempDirectory: URL?

    override func setUp() async throws {
        try await super.setUp()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileStorageManagerTests-\(UUID().uuidString)", isDirectory: true)
        tempDirectory = directory
        do {
            manager = try FileStorageManager(imageDirectory: directory)
        } catch {
            XCTFail("Failed to initialize FileStorageManager: \(error)")
        }
    }

    override func tearDown() async throws {
        manager = nil
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        tempDirectory = nil
        try await super.tearDown()
    }

    /// The injectable directory is honored: files land inside the temporary
    /// directory (which init creates), not in the default Application Support
    /// location (#0034).
    func testInitWithCustomDirectoryStoresFilesThere() async throws {
        guard let manager = manager, let tempDirectory = tempDirectory else {
            XCTFail("FileStorageManager not initialized")
            return
        }

        var isDirectory: ObjCBool = false
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: tempDirectory.path, isDirectory: &isDirectory),
            "Init should create the injected directory"
        )
        XCTAssertTrue(isDirectory.boolValue, "The injected path should be a directory")

        let filename = try await manager.save(imageData: Data("isolation".utf8))
        let filePath = await manager.getFilePath(filename: filename)
        XCTAssertEqual(
            filePath, tempDirectory.appendingPathComponent(filename),
            "Saved files must live inside the injected directory"
        )
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: filePath.path),
            "The saved file should exist inside the temporary directory"
        )
    }

    func testSaveAndLoadImageData() async throws {
        guard let manager = manager else {
            XCTFail("FileStorageManager not initialized")
            return
        }

        // Create test image data
        let testData = "Test image data".data(using: .utf8)!

        // Save the image
        let filename = try await manager.save(imageData: testData)
        XCTAssertFalse(filename.isEmpty, "Filename should not be empty")
        XCTAssertTrue(filename.hasSuffix(".dat"), "Filename should end with .dat")

        // Load the image back
        let loadedData = try await manager.load(filename: filename)
        XCTAssertEqual(loadedData, testData, "Loaded data should match saved data")
    }

    func testFileExists() async throws {
        guard let manager = manager else {
            XCTFail("FileStorageManager not initialized")
            return
        }

        let testData = "Existence test".data(using: .utf8)!
        let filename = try await manager.save(imageData: testData)

        // Check existence
        let exists = await manager.exists(filename: filename)
        XCTAssertTrue(exists, "File should exist after saving")

        // Delete and check again
        try await manager.delete(filename: filename)
        let existsAfterDelete = await manager.exists(filename: filename)
        XCTAssertFalse(existsAfterDelete, "File should not exist after deletion")
    }

    func testLoadNonexistentFile() async throws {
        guard let manager = manager else {
            XCTFail("FileStorageManager not initialized")
            return
        }

        let nonexistentFilename = "nonexistent-\(UUID().uuidString).dat"
        let loadedData = try await manager.load(filename: nonexistentFilename)
        XCTAssertNil(loadedData, "Loading a nonexistent file should return nil")
    }

    func testDeleteNonexistentFile() async throws {
        guard let manager = manager else {
            XCTFail("FileStorageManager not initialized")
            return
        }

        let nonexistentFilename = "nonexistent-\(UUID().uuidString).dat"
        // Should not throw for nonexistent files
        try await manager.delete(filename: nonexistentFilename)
    }

    /// Mirrors the import path used by `GalleryCoordinator.createGalleryItem`:
    /// the original image bytes are saved, loaded back byte-for-byte, and the
    /// loaded data decodes to the same real pixel dimensions.
    func testImageRoundTripPreservesBytesAndDimensions() async throws {
        guard let manager = manager else {
            XCTFail("FileStorageManager not initialized")
            return
        }

        let expectedWidth = 7
        let expectedHeight = 11
        let pngData = try Self.makePNGData(width: expectedWidth, height: expectedHeight)

        let filename = try await manager.save(imageData: pngData)

        let loaded = try await manager.load(filename: filename)
        XCTAssertEqual(loaded, pngData, "Loaded image bytes should match what was saved")

        let cgImage = try XCTUnwrap(Self.decode(loaded), "Loaded bytes should decode to a CGImage")
        XCTAssertEqual(cgImage.width, expectedWidth, "Decoded width should match the original")
        XCTAssertEqual(cgImage.height, expectedHeight, "Decoded height should match the original")
    }

    /// Generate a solid-color PNG of the given size, platform-independently.
    private static func makePNGData(width: Int, height: Int) throws -> Data {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try XCTUnwrap(context.makeImage())

        let mutableData = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(
            mutableData, UTType.png.identifier as CFString, 1, nil
        ))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination), "Failed to encode PNG")
        return mutableData as Data
    }

    private static func decode(_ data: Data?) -> CGImage? {
        guard let data,
              let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
