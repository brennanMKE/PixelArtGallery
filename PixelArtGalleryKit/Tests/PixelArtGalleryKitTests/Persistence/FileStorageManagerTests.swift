import XCTest
@testable import PixelArtGalleryKit

final class FileStorageManagerTests: XCTestCase {
    var manager: FileStorageManager?

    override func setUp() async throws {
        try await super.setUp()
        do {
            manager = try await FileStorageManager()
        } catch {
            XCTFail("Failed to initialize FileStorageManager: \(error)")
        }
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
}
