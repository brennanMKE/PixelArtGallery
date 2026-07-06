import SwiftUI

/// Modal view for editing an existing variant's target dimensions.
///
/// Prefills the width/height fields from the variant's current size. Saving
/// re-runs the pixelation engine at the new dimensions (PRD §2 "Variant
/// Management"), which the caller wires to
/// ``GalleryCoordinator/updateVariantDimensions(_:width:height:)``. Mirrors
/// ``VariantCreationView`` in style and validation.
struct VariantEditDimensionsView: View {
    @Environment(\.dismiss) var dismiss

    @State private var width: String
    @State private var height: String
    @State private var isLoading = false
    @State private var errorMessage: String?

    /// Applies the new dimensions, regenerating the variant's pixel data.
    var onSave: (Int, Int) async -> Void

    init(width: Int, height: Int, onSave: @escaping (Int, Int) async -> Void) {
        _width = State(initialValue: String(width))
        _height = State(initialValue: String(height))
        self.onSave = onSave
    }

    var isValid: Bool {
        if let w = Int(width), let h = Int(height) {
            return w > 0 && w <= 512 && h > 0 && h <= 512
        }
        return false
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Target Dimensions") {
                    HStack {
                        Text("Width (pixels)")
                        Spacer()
                        TextField("Width", text: $width)
                            .textFieldStyle(.roundedBorder)
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            #else
                            .labelsHidden()
                            #endif
                            .frame(width: 100)
                    }

                    HStack {
                        Text("Height (pixels)")
                        Spacer()
                        TextField("Height", text: $height)
                            .textFieldStyle(.roundedBorder)
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            #else
                            .labelsHidden()
                            #endif
                            .frame(width: 100)
                    }

                    if let error = errorMessage {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }

                Section("Constraints") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "info.circle.fill")
                                .foregroundStyle(.blue)
                            Text("Width and height must be between 1 and 512 pixels")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        HStack {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .foregroundStyle(.blue)
                            Text("Saving regenerates the pixel data from the original image")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Edit Dimensions")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    if isLoading {
                        ProgressView()
                    } else {
                        Button("Save") {
                            save()
                        }
                        .disabled(!isValid)
                    }
                }
            }
        }
        #if os(macOS)
        // Sheets on macOS don't size themselves to a Form's content; without an
        // explicit frame the sheet collapses and the form rows are invisible (#0025,
        // same defect as #0024). Smaller than Create Variant — no display picker here.
        .frame(minWidth: 440, minHeight: 360)
        #endif
    }

    private func save() {
        guard let targetWidth = Int(width), let targetHeight = Int(height) else {
            errorMessage = "Invalid dimensions"
            return
        }

        guard targetWidth > 0, targetWidth <= 512, targetHeight > 0, targetHeight <= 512 else {
            errorMessage = "Dimensions must be between 1 and 512"
            return
        }

        errorMessage = nil
        isLoading = true

        Task {
            await onSave(targetWidth, targetHeight)
            isLoading = false
            dismiss()
        }
    }
}

#Preview {
    VariantEditDimensionsView(width: 32, height: 32, onSave: { _, _ in })
}
