import SwiftUI

/// Shows a selected gallery item with original image and variants list
struct GalleryDetailView: View {
    let item: GalleryItem
    let coordinator: GalleryCoordinator

    /// The variant pending a delete confirmation, if any.
    @State private var variantToDelete: Variant?
    /// The variant whose dimensions are being edited in a sheet, if any.
    @State private var variantToEdit: Variant?
    /// Whether the rename alert for this item is showing.
    @State private var isRenaming = false
    /// Working text for the rename alert's text field.
    @State private var renameText: String = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Original image preview
                VStack(alignment: .leading) {
                    Text("Original Image")
                        .font(.headline)

                    StoredImageView(
                        path: item.originalImagePath,
                        maxPixelSize: 2048,
                        coordinator: coordinator,
                        contentMode: .fit
                    ) {
                        Image(systemName: "photo.fill")
                            .resizable()
                            .scaledToFit()
                            .padding(40)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 200)
                    .background(Color.gray.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    if item.originalWidth > 0 && item.originalHeight > 0 {
                        Text("\(item.originalWidth)×\(item.originalHeight) px")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // Variants list
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Variants")
                            .font(.headline)
                        Spacer()
                        Button(action: {
                            coordinator.selectedItem = item
                            coordinator.showVariantCreation = true
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "plus.circle.fill")
                                Text("Create")
                            }
                            .font(.caption)
                            .foregroundColor(.blue)
                        }
                    }

                    if item.variants.isEmpty {
                        Text("No variants created yet")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding()
                    } else {
                        ForEach(item.variants) { variant in
                            NavigationLink(value: variant) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("\(variant.targetWidth)×\(variant.targetHeight)")
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                        if let format = variant.exportFormat {
                                            Text(format)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        Text(variant.createdDate, style: .date)
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }
                                    Spacer()
                                    Image(systemName: "arrow.right")
                                        .foregroundColor(.blue)
                                }
                                .padding()
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(8)
                            }
                            .contextMenu {
                                Button {
                                    variantToEdit = variant
                                } label: {
                                    Label("Edit Dimensions", systemImage: "ruler")
                                }
                                Button {
                                    try? coordinator.duplicateVariant(variant)
                                } label: {
                                    Label("Duplicate", systemImage: "plus.square.on.square")
                                }
                                Button(role: .destructive) {
                                    variantToDelete = variant
                                } label: {
                                    Label("Delete Variant", systemImage: "trash")
                                }
                            }
                            #if os(iOS)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    variantToDelete = variant
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                Button {
                                    variantToEdit = variant
                                } label: {
                                    Label("Edit", systemImage: "ruler")
                                }
                                .tint(.blue)
                                Button {
                                    try? coordinator.duplicateVariant(variant)
                                } label: {
                                    Label("Duplicate", systemImage: "plus.square.on.square")
                                }
                                .tint(.indigo)
                            }
                            #endif
                        }
                    }
                }

                Spacer()
            }
            .padding()
        }
        .navigationTitle(item.originalName)
        .navigationDestination(for: Variant.self) { variant in
            VariantDetailView(variant: variant, coordinator: coordinator)
        }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    renameText = item.originalName
                    isRenaming = true
                } label: {
                    Label("Rename", systemImage: "pencil")
                }
            }
        }
        .alert("Rename Image", isPresented: $isRenaming) {
            TextField("Imported Image", text: $renameText)
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                coordinator.renameGalleryItem(item, to: renameText)
            }
        } message: {
            Text("Enter a new name for this image.")
        }
        .confirmationDialog(
            "Delete this variant?",
            isPresented: Binding(
                get: { variantToDelete != nil },
                set: { if !$0 { variantToDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: variantToDelete
        ) { variant in
            Button("Delete Variant", role: .destructive) {
                coordinator.deleteVariant(variant)
                variantToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                variantToDelete = nil
            }
        } message: { variant in
            Text("\(variant.targetWidth)×\(variant.targetHeight) — this can't be undone.")
        }
        .sheet(item: $variantToEdit) { variant in
            VariantEditDimensionsView(
                width: variant.targetWidth,
                height: variant.targetHeight
            ) { width, height in
                try? await coordinator.updateVariantDimensions(variant, width: width, height: height)
            }
        }
    }
}

#Preview {
    // Create a preview gallery item with a sample variant
    let sampleItem = GalleryItem(
        originalImagePath: "sample.jpg",
        originalName: "Sample Image",
        originalWidth: 800,
        originalHeight: 600
    )

    NavigationStack {
        GalleryDetailView(item: sampleItem, coordinator: GalleryCoordinator())
    }
}
