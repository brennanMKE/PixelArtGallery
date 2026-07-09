import SwiftData
import SwiftUI

/// App settings surface for managing Flaschen Taschen displays (#0054).
///
/// Display management — scan, add, edit, and delete every persisted
/// ``FlaschenTaschenDisplay`` — is a first-class part of Settings rather than a
/// separate destination buried in the gallery toolbar. The seeded default
/// display is no longer special-cased here: it's an ordinary editable row
/// (labeled "Default") in the same registry ``DisplayRegistryView`` shows, with
/// a "Restore Default Display" affordance if it's ever deleted.
///
/// The same view backs both platforms: macOS presents it in a `Settings` scene
/// (⌘,), iOS in a sheet reached from the gallery toolbar's gear button. Because
/// the `Settings` scene has no `GalleryCoordinator` of its own, this view owns
/// one and configures it with the environment's `ModelContext` — the scene
/// already gets `.modelContainer(modelContainer)` in `PixelArtGalleryApp`.
public struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var coordinator = GalleryCoordinator()

    public init() {}

    public var body: some View {
        NavigationStack {
            DisplayRegistryView(coordinator: coordinator)
                #if os(iOS)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
                #endif
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 480)
        #endif
        .onAppear {
            coordinator.configure(modelContext: modelContext)
        }
    }
}

#Preview {
    SettingsView()
}
