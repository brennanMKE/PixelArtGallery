import Foundation
import SwiftUI

/// Mock gallery models for UI development and testing
public struct MockGalleryItem: Identifiable, Sendable, Hashable {
    public let id: UUID
    public let name: String
    /// Image data (platform-agnostic)
    public let imageData: Data?
    public let importDate: Date
    public let variantCount: Int

    public init(
        id: UUID = UUID(),
        name: String,
        imageData: Data? = nil,
        importDate: Date = Date(),
        variantCount: Int = 0
    ) {
        self.id = id
        self.name = name
        self.imageData = imageData
        self.importDate = importDate
        self.variantCount = variantCount
    }

    @MainActor
    public static let samples = [
        MockGalleryItem(name: "Nature Scene", variantCount: 3),
        MockGalleryItem(name: "Portrait", variantCount: 2),
        MockGalleryItem(name: "Still Life", variantCount: 1),
    ]
}

public struct MockVariant: Identifiable, Sendable, Hashable {
    public let id: UUID
    public let width: Int
    public let height: Int
    public let createdDate: Date
    public let exportFormat: String

    public init(
        id: UUID = UUID(),
        width: Int,
        height: Int,
        createdDate: Date = Date(),
        exportFormat: String = "PNG"
    ) {
        self.id = id
        self.width = width
        self.height = height
        self.createdDate = createdDate
        self.exportFormat = exportFormat
    }

    @MainActor
    public static let samples = [
        MockVariant(width: 32, height: 32),
        MockVariant(width: 64, height: 64),
        MockVariant(width: 128, height: 128),
    ]
}
