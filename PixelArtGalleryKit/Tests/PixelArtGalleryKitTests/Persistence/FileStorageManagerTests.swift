import Testing
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import PixelArtGalleryKit

@Suite final class FileStorageManagerTests {
    private let manager: FileStorageManager

    /// Unique per-test temporary directory the manager stores files in, so the
    /// suite never touches the real `Application Support/PixelArtGallery/Images`
    /// directory the app uses (#0034). Created in `init`, removed in `deinit`.
    private let tempDirectory: URL

    init() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileStorageManagerTests-\(UUID().uuidString)", isDirectory: true)
        tempDirectory = directory
        manager = try FileStorageManager(imageDirectory: directory)
    }

    deinit {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    /// The injectable directory is honored: files land inside the temporary
    /// directory (which init creates), not in the default Application Support
    /// location (#0034).
    @Test func initWithCustomDirectoryStoresFilesThere() async throws {
        var isDirectory: ObjCBool = false
        #expect(
            FileManager.default.fileExists(atPath: tempDirectory.path, isDirectory: &isDirectory),
            "Init should create the injected directory"
        )
        #expect(isDirectory.boolValue, "The injected path should be a directory")

        let filename = try await manager.save(imageData: Data("isolation".utf8))
        let filePath = await manager.getFilePath(filename: filename)
        #expect(
            filePath == tempDirectory.appendingPathComponent(filename),
            "Saved files must live inside the injected directory"
        )
        #expect(
            FileManager.default.fileExists(atPath: filePath.path),
            "The saved file should exist inside the temporary directory"
        )
    }

    @Test func saveAndLoadImageData() async throws {
        // Create test image data
        let testData = "Test image data".data(using: .utf8)!

        // Save the image
        let filename = try await manager.save(imageData: testData)
        #expect(!filename.isEmpty, "Filename should not be empty")
        #expect(filename.hasSuffix(".dat"), "Filename should end with .dat")

        // Load the image back
        let loadedData = try await manager.load(filename: filename)
        #expect(loadedData == testData, "Loaded data should match saved data")
    }

    @Test func fileExists() async throws {
        let testData = "Existence test".data(using: .utf8)!
        let filename = try await manager.save(imageData: testData)

        // Check existence
        let exists = await manager.exists(filename: filename)
        #expect(exists, "File should exist after saving")

        // Delete and check again
        try await manager.delete(filename: filename)
        let existsAfterDelete = await manager.exists(filename: filename)
        #expect(!existsAfterDelete, "File should not exist after deletion")
    }

    @Test func loadNonexistentFile() async throws {
        let nonexistentFilename = "nonexistent-\(UUID().uuidString).dat"
        let loadedData = try await manager.load(filename: nonexistentFilename)
        #expect(loadedData == nil, "Loading a nonexistent file should return nil")
    }

    @Test func deleteNonexistentFile() async throws {
        let nonexistentFilename = "nonexistent-\(UUID().uuidString).dat"
        // Should not throw for nonexistent files
        try await manager.delete(filename: nonexistentFilename)
    }

    /// Mirrors the import path used by `GalleryCoordinator.createGalleryItem`:
    /// the original image bytes are saved, loaded back byte-for-byte, and the
    /// loaded data decodes to the same real pixel dimensions.
    @Test func imageRoundTripPreservesBytesAndDimensions() async throws {
        let expectedWidth = 7
        let expectedHeight = 11
        let pngData = try Self.makePNGData(width: expectedWidth, height: expectedHeight)

        let filename = try await manager.save(imageData: pngData)

        let loaded = try await manager.load(filename: filename)
        #expect(loaded == pngData, "Loaded image bytes should match what was saved")

        let cgImage = try #require(Self.decode(loaded), "Loaded bytes should decode to a CGImage")
        #expect(cgImage.width == expectedWidth, "Decoded width should match the original")
        #expect(cgImage.height == expectedHeight, "Decoded height should match the original")
    }

    /// Generate a solid-color PNG of the given size, platform-independently.
    private static func makePNGData(width: Int, height: Int) throws -> Data {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try #require(CGContext(
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
        let image = try #require(context.makeImage())

        let mutableData = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(
            mutableData, UTType.png.identifier as CFString, 1, nil
        ))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination), "Failed to encode PNG")
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
