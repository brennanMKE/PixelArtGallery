import Foundation

/// Actor responsible for managing file I/O operations for original images.
/// Handles saving, loading, and deleting image data to/from the Application Support directory
/// by default, or a caller-supplied directory (used by tests to stay out of real user data).
/// Uses UUID-based filenames to ensure uniqueness and avoid collisions.
actor FileStorageManager {
    /// Base directory for image storage
    private let imageDirectory: URL

    /// Initialize the FileStorageManager and ensure the storage directory exists.
    /// - Parameter imageDirectory: Directory to store image files in. Pass `nil`
    ///   (the default) to use the production location,
    ///   `Application Support/PixelArtGallery/Images`. Tests inject a temporary
    ///   directory here so they never touch the user's real gallery storage.
    init(imageDirectory: URL? = nil) throws {
        if let imageDirectory {
            self.imageDirectory = imageDirectory
        } else {
            // Get Application Support directory
            guard let appSupportURL = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first else {
                throw FileStorageError.directoryAccessDenied
            }

            // Create the per-identity subdirectory (PixelArtGallery, or
            // PixelArtGallery-Beta for the .beta bundle ID — #0045)
            let pixelArtGalleryURL = appSupportURL.appendingPathComponent(StorageFolder.current, isDirectory: true)
            self.imageDirectory = pixelArtGalleryURL.appendingPathComponent("Images", isDirectory: true)
        }

        // Ensure the directory exists
        try FileManager.default.createDirectory(
            at: self.imageDirectory,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }

    /// Save image data to disk with a UUID-based filename
    /// - Parameter imageData: The image data to save
    /// - Returns: The filename (UUID string) where the image was saved
    /// - Throws: FileStorageError if save operation fails
    func save(imageData: Data) throws -> String {
        let filename = UUID().uuidString + ".dat"
        let fileURL = imageDirectory.appendingPathComponent(filename)

        do {
            try imageData.write(to: fileURL, options: .atomic)
            return filename
        } catch {
            throw FileStorageError.saveFailed(filename, underlyingError: error)
        }
    }

    /// Load image data from disk
    /// - Parameter filename: The filename (as returned by save) to load
    /// - Returns: The image data, or nil if file doesn't exist
    /// - Throws: FileStorageError if read operation fails
    func load(filename: String) throws -> Data? {
        let fileURL = imageDirectory.appendingPathComponent(filename)

        // Check if file exists first
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }

        do {
            return try Data(contentsOf: fileURL, options: .mappedIfSafe)
        } catch {
            throw FileStorageError.loadFailed(filename, underlyingError: error)
        }
    }

    /// Delete image data from disk
    /// - Parameter filename: The filename to delete
    /// - Throws: FileStorageError if delete operation fails
    func delete(filename: String) throws {
        let fileURL = imageDirectory.appendingPathComponent(filename)

        // Only attempt deletion if file exists
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return
        }

        do {
            try FileManager.default.removeItem(at: fileURL)
        } catch {
            throw FileStorageError.deleteFailed(filename, underlyingError: error)
        }
    }

    /// Check if a file exists on disk
    /// - Parameter filename: The filename to check
    /// - Returns: True if the file exists, false otherwise
    func exists(filename: String) -> Bool {
        let fileURL = imageDirectory.appendingPathComponent(filename)
        return FileManager.default.fileExists(atPath: fileURL.path)
    }

    /// Get the full URL path for a stored file
    /// - Parameter filename: The filename
    /// - Returns: The full file URL
    func getFilePath(filename: String) -> URL {
        imageDirectory.appendingPathComponent(filename)
    }
}

/// Errors that can occur during file storage operations
enum FileStorageError: LocalizedError {
    case directoryAccessDenied
    case saveFailed(String, underlyingError: Error)
    case loadFailed(String, underlyingError: Error)
    case deleteFailed(String, underlyingError: Error)

    var errorDescription: String? {
        switch self {
        case .directoryAccessDenied:
            return "Unable to access Application Support directory"
        case .saveFailed(let filename, let error):
            return "Failed to save image '\(filename)': \(error.localizedDescription)"
        case .loadFailed(let filename, let error):
            return "Failed to load image '\(filename)': \(error.localizedDescription)"
        case .deleteFailed(let filename, let error):
            return "Failed to delete image '\(filename)': \(error.localizedDescription)"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .directoryAccessDenied:
            return "Check file system permissions or restart the app"
        case .saveFailed:
            return "Ensure sufficient disk space is available"
        case .loadFailed:
            return "The image file may have been deleted or moved"
        case .deleteFailed:
            return "The image file may be in use or permissions may be insufficient"
        }
    }
}
