import SwiftUI

/// Displays a list of all gallery items with preview thumbnails
struct GalleryListView: View {
    @State private var coordinator = GalleryCoordinator()
    @Environment(\.horizontalSizeClass) var horizontalSizeClass

    var body: some View {
        NavigationStack {
            Group {
                if coordinator.galleryItems.isEmpty {
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
                    List(coordinator.galleryItems) { item in
                        NavigationLink(value: item) {
                            HStack(spacing: 12) {
                                // Thumbnail placeholder
                                Image(systemName: "photo.fill")
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 60, height: 60)
                                    .background(Color.gray.opacity(0.2))
                                    .cornerRadius(8)

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
                    }
                    .navigationDestination(for: GalleryItem.self) { item in
                        GalleryDetailView(item: item, coordinator: coordinator)
                    }
                }
            }
            .navigationTitle("Gallery")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { coordinator.showImagePicker = true }) {
                        Image(systemName: "plus")
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
        }

        // Image picker sheet
        .sheet(isPresented: $coordinator.showImagePicker) {
            ImagePickerView { imageData in
                Task {
                    let imageName = "Imported Image"
                    try? coordinator.createGalleryItem(name: imageName, imageData: imageData)
                }
            }
        }

        // Variant creation sheet
        .sheet(isPresented: $coordinator.showVariantCreation) {
            if let selectedItem = coordinator.selectedItem {
                VariantCreationView { width, height in
                    await coordinator.createVariant(for: selectedItem, width: width, height: height)
                }
            }
        }
    }
}

#Preview {
    GalleryListView()
}
