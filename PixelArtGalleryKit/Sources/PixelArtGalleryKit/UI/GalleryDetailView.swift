import SwiftUI

/// Shows a selected gallery item with original image and variants list
struct GalleryDetailView: View {
    let item: GalleryItem
    let coordinator: GalleryCoordinator

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Original image preview
                VStack(alignment: .leading) {
                    Text("Original Image")
                        .font(.headline)

                    VStack {
                        Image(systemName: "photo.fill")
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity)
                            .frame(height: 200)
                            .background(Color.gray.opacity(0.2))
                    }
                    .cornerRadius(12)

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
