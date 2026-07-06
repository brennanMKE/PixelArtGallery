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

        // Per-identity folder: "PixelArtGallery" for release,
        // "PixelArtGallery-Beta" for the .beta (Debug) bundle ID (#0045).
        let pixelArtGalleryURL = appSupportURL.appendingPathComponent(StorageFolder.current, isDirectory: true)

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
        // App menu: replace the standard About item so a divider and
        // "Check for Updates…" (Sparkle, #0038) sit directly beneath it. The
        // update item stays disabled until the Sparkle feed URL is wired
        // into Info.plist (#0039).
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Pixel Art Gallery") {
                    NSApplication.shared.orderFrontStandardAboutPanel(nil)
                }
                Divider()
                Button("Check for Updates…") {
                    UpdaterController.shared.checkForUpdates()
                }
                .disabled(!UpdaterController.shared.isConfigured)
            }
        }
        #endif

        // macOS Settings scene (Pixel Art Gallery ▸ Settings…, ⌘,) editing the
        // default Flaschen Taschen display (#0021). Needs its own
        // `.modelContainer` — scenes don't inherit the WindowGroup's.
        #if os(macOS)
        Settings {
            SettingsView()
        }
        .modelContainer(modelContainer)
        #endif
    }
}
