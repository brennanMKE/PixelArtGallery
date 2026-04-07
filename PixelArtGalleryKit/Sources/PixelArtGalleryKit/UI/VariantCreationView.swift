import SwiftUI

/// Modal view for creating a new variant with custom dimensions
struct VariantCreationView: View {
    @Environment(\.dismiss) var dismiss
    @State private var width: String = "32"
    @State private var height: String = "32"
    @State private var isLoading = false
    @State private var errorMessage: String?

    var onCreateVariant: (Int, Int) async -> Void

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
                            .keyboardType(.numberPad)
                            .frame(width: 100)
                    }

                    HStack {
                        Text("Height (pixels)")
                        Spacer()
                        TextField("Height", text: $height)
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.numberPad)
                            .frame(width: 100)
                    }

                    if let error = errorMessage {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }

                Section("Constraints") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "info.circle.fill")
                                .foregroundColor(.blue)
                            Text("Width and height must be between 1 and 512 pixels")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        HStack {
                            Image(systemName: "info.circle.fill")
                                .foregroundColor(.blue)
                            Text("Smaller dimensions create more abstract pixel art")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Create Variant")
            .navigationBarTitleDisplayMode(.inline)
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
                        Button("Create Variant") {
                            createVariant()
                        }
                        .disabled(!isValid)
                    }
                }
            }
        }
    }

    private func createVariant() {
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
            await onCreateVariant(targetWidth, targetHeight)
            isLoading = false
            dismiss()
        }
    }
}

#Preview {
    VariantCreationView(onCreateVariant: { _, _ in })
}
