import SwiftUI

/// Shows a selected gallery item: its original photo and a list of pixel-art variants.
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
        List {
            Section {
                photo
                    .listRowInsets(EdgeInsets(
                        top: Theme.Spacing.s, leading: Theme.Spacing.l,
                        bottom: Theme.Spacing.s, trailing: Theme.Spacing.l
                    ))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }

            Section {
                if item.variants.isEmpty {
                    EmptyStateView(
                        icon: "square.grid.2x2",
                        title: "No variants yet",
                        message: "Create a pixelated variant at a target size to preview and send it.",
                        actionLabel: "Create Variant",
                        action: startVariantCreation
                    )
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(item.variants) { variant in
                        NavigationLink(value: variant) {
                            variantRow(variant)
                        }
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
                                _ = try? coordinator.duplicateVariant(variant)
                            } label: {
                                Label("Duplicate", systemImage: "plus.square.on.square")
                            }
                            .tint(.indigo)
                        }
                        .contextMenu {
                            Button {
                                variantToEdit = variant
                            } label: {
                                Label("Edit Dimensions", systemImage: "ruler")
                            }
                            Button {
                                _ = try? coordinator.duplicateVariant(variant)
                            } label: {
                                Label("Duplicate", systemImage: "plus.square.on.square")
                            }
                            Button(role: .destructive) {
                                variantToDelete = variant
                            } label: {
                                Label("Delete Variant", systemImage: "trash")
                            }
                        }
                    }
                }
            } header: {
                Text("Variants")
            }
        }
        .scrollContentBackground(.hidden)
        .navigationTitle(item.originalName)
        .navigationDestination(for: Variant.self) { variant in
            VariantDetailView(variant: variant, coordinator: coordinator)
        }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: startVariantCreation) {
                    Label("Create Variant", systemImage: "plus")
                }
            }
            ToolbarItem(placement: .secondaryAction) {
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

    /// The original photo, shown at natural aspect ratio with a dimensions caption.
    private var photo: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            StoredImageView(
                path: item.originalImagePath,
                maxPixelSize: 2048,
                coordinator: coordinator,
                contentMode: .fit
            ) {
                Image(systemName: "photo.fill")
                    .resizable()
                    .scaledToFit()
                    .padding(Theme.Spacing.xl)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .frame(maxHeight: 320)
            .card(padding: 0)

            if item.originalWidth > 0 && item.originalHeight > 0 {
                Text("\(item.originalWidth)×\(item.originalHeight) px")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// A single variant row: pixel-art thumbnail plus dimensions and metadata.
    private func variantRow(_ variant: Variant) -> some View {
        HStack(spacing: Theme.Spacing.m) {
            VariantThumbnailView(variant: variant)
                .frame(width: 52, height: 52)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("\(variant.targetWidth)×\(variant.targetHeight)")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                if let format = variant.exportFormat {
                    Text(format)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(variant.createdDate, style: .date)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, Theme.Spacing.xs)
    }

    private func startVariantCreation() {
        coordinator.selectedItem = item
        coordinator.showVariantCreation = true
    }
}

#Preview {
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
