import SwiftData
import SwiftUI

/// Non-model navigation destinations reachable from the gallery's nav stack.
/// Model-backed pushes (a `GalleryItem`) use their own `navigationDestination`.
enum GalleryRoute: Hashable {
    /// The Flaschen Taschen display registry.
    case displays
}

/// Displays a list of all gallery items with preview thumbnails
/// A freshly picked image awaiting a name before it's imported. Carries the raw
/// bytes plus the picker's suggested name (if any) so the naming sheet can
/// prefill the field.
private struct PendingImport: Identifiable {
    let id = UUID()
    let imageData: Data
    let suggestedName: String?
}

/// Displays a list of all gallery items with preview thumbnails
public struct GalleryListView: View {
    @State private var coordinator = GalleryCoordinator()
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.modelContext) private var modelContext

    /// A picked image awaiting naming, which drives the import naming sheet.
    @State private var pendingImport: PendingImport?
    /// The gallery item currently being renamed via the rename alert, if any.
    @State private var itemToRename: GalleryItem?
    /// Working text for the rename alert's text field.
    @State private var renameText: String = ""

    /// Live, auto-updating gallery items sourced directly from SwiftData.
    /// The view owns the query; the coordinator only handles mutations.
    @Query(sort: \GalleryItem.importedDate, order: .reverse) private var galleryItems: [GalleryItem]

    public init() {}

    public var body: some View {
        NavigationStack {
            Group {
                if galleryItems.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 48))
                            .foregroundColor(.gray)
                        Text("No Gallery Items")
                            .font(.headline)
                        Text("Import an image to get started")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Button(action: { coordinator.showImagePicker = true }) {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                Text("Import Image")
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 32)
                            .padding(.vertical, 12)
                            .background(Color.blue)
                            .cornerRadius(8)
                        }
                        .padding(.top, 16)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(galleryItems) { item in
                        NavigationLink(value: item) {
                            HStack(spacing: 12) {
                                // Thumbnail of the imported original image.
                                StoredImageView(
                                    path: item.originalImagePath,
                                    maxPixelSize: 180,
                                    coordinator: coordinator
                                ) {
                                    Image(systemName: "photo.fill")
                                        .resizable()
                                        .scaledToFit()
                                        .padding(14)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(width: 60, height: 60)
                                .background(Color.gray.opacity(0.2))
                                .clipShape(RoundedRectangle(cornerRadius: 8))

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.originalName)
                                        .font(.headline)
                                    Text(item.importedDate, style: .date)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text("\(item.variants.count) variant\(item.variants.count != 1 ? "s" : "")")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .contextMenu {
                            Button {
                                renameText = item.originalName
                                itemToRename = item
                            } label: {
                                Label("Rename", systemImage: "pencil")
                            }
                        }
                        }
                        .onDelete { offsets in
                            for index in offsets {
                                coordinator.deleteGalleryItem(galleryItems[index])
                            }
                        }
                    }
                }
            }
            .navigationDestination(for: GalleryItem.self) { item in
                GalleryDetailView(item: item, coordinator: coordinator)
            }
            .navigationDestination(for: GalleryRoute.self) { route in
                switch route {
                case .displays:
                    DisplayRegistryView(coordinator: coordinator)
                }
            }
            .navigationTitle("Gallery")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { coordinator.showImagePicker = true }) {
                        Image(systemName: "plus")
                    }
                }
                ToolbarItem(placement: .secondaryAction) {
                    NavigationLink(value: GalleryRoute.displays) {
                        Label("Displays", systemImage: "display")
                    }
                }
            }

            // Error alert
            .alert("Error", isPresented: .constant(coordinator.currentError != nil)) {
                Button("OK") {
                    coordinator.currentError = nil
                }
            } message: {
                Text(coordinator.currentError ?? "")
            }

            // Informational alert (e.g. a duplicate import was skipped). Not an
            // error — surfaces the coordinator's non-error import message.
            .alert("Import", isPresented: .constant(coordinator.importMessage != nil)) {
                Button("OK") {
                    coordinator.importMessage = nil
                }
            } message: {
                Text(coordinator.importMessage ?? "")
            }
            .onAppear {
                coordinator.configure(modelContext: modelContext)
            }
            // Rename an existing gallery item.
            .alert("Rename Image", isPresented: Binding(
                get: { itemToRename != nil },
                set: { if !$0 { itemToRename = nil } }
            )) {
                TextField("Imported Image", text: $renameText)
                Button("Cancel", role: .cancel) {
                    itemToRename = nil
                }
                Button("Rename") {
                    if let item = itemToRename {
                        coordinator.renameGalleryItem(item, to: renameText)
                    }
                    itemToRename = nil
                }
            } message: {
                Text("Enter a new name for this image.")
            }
        }

        // Image picker sheet. Picking surfaces the bytes plus a suggested name,
        // which we hold as a pending import so the user can confirm/edit the name
        // before it's saved.
        .sheet(isPresented: $coordinator.showImagePicker) {
            ImagePickerView { imageData, suggestedName in
                pendingImport = PendingImport(imageData: imageData, suggestedName: suggestedName)
            }
        }

        // Import naming sheet — prefilled with the suggested name.
        .sheet(item: $pendingImport) { pending in
            ImportNamingView(suggestedName: pending.suggestedName) { name in
                try? await coordinator.createGalleryItem(name: name, imageData: pending.imageData)
            }
        }

        // Variant creation sheet
        .sheet(isPresented: $coordinator.showVariantCreation) {
            if let selectedItem = coordinator.selectedItem {
                VariantCreationView { width, height, associatedDisplayId in
                    try? await coordinator.createVariant(
                        for: selectedItem,
                        width: width,
                        height: height,
                        associatedDisplayId: associatedDisplayId
                    )
                }
            }
        }
    }
}

#Preview {
    GalleryListView()
}
