// PixelArtGalleryApp.swift

import SwiftUI
import SwiftData
import PixelArtGalleryKit

@main
struct PixelArtGalleryApp: App {
    /// Initialize SwiftData ModelContainer for all gallery models
    private let modelContainer: ModelContainer

    init() {
        // Configure SwiftData models
        let schema = Schema([
            GalleryItem.self,
            Variant.self,
            FlaschenTaschenDisplay.self,
        ])

        let modelConfiguration = ModelConfiguration(
            schema: schema,
            url: Self.getGalleryDatabaseURL(),
            cloudKitDatabase: .none
        )

        do {
            self.modelContainer = try ModelContainer(
                for: schema,
                configurations: [modelConfiguration]
            )
        } catch {
            fatalError("Could not initialize ModelContainer: \(error)")
        }
    }

    /// Get the database file URL for gallery data
    private static func getGalleryDatabaseURL() -> URL {
        guard let appSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            fatalError("Unable to access Application Support directory")
        }

        let pixelArtGalleryURL = appSupportURL.appendingPathComponent("PixelArtGallery", isDirectory: true)

        // Ensure the directory exists
        do {
            try FileManager.default.createDirectory(
                at: pixelArtGalleryURL,
                withIntermediateDirectories: true,
                attributes: nil
            )
        } catch {
            fatalError("Unable to create PixelArtGallery directory: \(error)")
        }

        return pixelArtGalleryURL.appendingPathComponent("gallery.db")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                #if os(macOS)
                .frame(minWidth: 640, minHeight: 480)
                #endif
        }
        .modelContainer(modelContainer)
        #if os(macOS)
        .defaultSize(width: 1000, height: 700)
        #endif
    }
}
