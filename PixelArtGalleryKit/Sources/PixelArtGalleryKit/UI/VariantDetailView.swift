import SwiftUI
import os.log

/// Shows details of a single variant with preview and export options
struct VariantDetailView: View {
    let variant: Variant
    let coordinator: GalleryCoordinator
    @State private var selectedExportFormat = "PNG"
    @State private var selectedDisplay = MockDisplay.samples[0]
    @State private var isExporting = false
    @State private var isSending = false
    @State private var showExportPicker = false
    @State private var successMessage: String?
    @State private var errorMessage: String?

    private static let logger = Logger(subsystem: "com.pixelartgallery.ui", category: "VariantDetailView")

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Variant info
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Dimensions")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("\(variant.targetWidth)×\(variant.targetHeight) px")
                                .font(.headline)
                        }
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text("Created")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(variant.createdDate, style: .date)
                                .font(.headline)
                        }
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)

                // Pixel grid preview
                VStack(alignment: .leading) {
                    Text("Preview")
                        .font(.headline)
                    PixelGridView(variant: variant)
                        .frame(height: 250)
                }

                // Export options
                VStack(alignment: .leading, spacing: 12) {
                    Text("Export")
                        .font(.headline)

                    Button(action: { showExportPicker = true }) {
                        HStack {
                            if isExporting {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Exporting...")
                            } else {
                                Image(systemName: "arrow.down.doc.fill")
                                Text("Export Variant")
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isExporting || isSending)
                }
                .sheet(isPresented: $showExportPicker) {
                    // Create mock variant for export picker
                    let mockVariant = MockVariant(
                        id: UUID(),
                        width: variant.targetWidth,
                        height: variant.targetHeight,
                        createdDate: variant.createdDate,
                        exportFormat: selectedExportFormat
                    )

                    ExportPickerView(
                        variant: mockVariant,
                        onExport: { format, url in
                            handleExport(format: format, url: url)
                        },
                        onCancel: {
                            showExportPicker = false
                        }
                    )
                }

                // Send to display
                VStack(alignment: .leading, spacing: 12) {
                    Text("Send to Display")
                        .font(.headline)

                    Picker("Display", selection: $selectedDisplay) {
                        ForEach(MockDisplay.samples) { display in
                            Text(display.name).tag(display)
                        }
                    }

                    Button(action: handleSendToDisplay) {
                        HStack {
                            if isSending {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Sending...")
                            } else {
                                Image(systemName: "arrow.up.right.circle.fill")
                                Text("Send Now")
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSending || isExporting)
                }

                // Status messages
                if let success = successMessage {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Success")
                                .fontWeight(.semibold)
                        }
                        Text(success)
                            .font(.caption)
                    }
                    .padding(12)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(6)
                    .transition(.opacity)
                }

                if let error = errorMessage {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundColor(.red)
                            Text("Error")
                                .fontWeight(.semibold)
                        }
                        Text(error)
                            .font(.caption)
                    }
                    .padding(12)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(6)
                    .transition(.opacity)
                }

                Spacer()
            }
            .padding()
        }
        .navigationTitle("Variant Details")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func handleExport(format: String, url: URL) {
        isExporting = true
        errorMessage = nil
        successMessage = nil

        Self.logger.debug("Starting export: format=\(format), path=\(url.path)")

        // Simulate export operation - in real implementation would call VariantExporter
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            isExporting = false
            showExportPicker = false
            successMessage = "Exported \(format) to \(url.lastPathComponent)"
            Self.logger.info("Export completed successfully")

            // Clear success message after 3 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                withAnimation {
                    successMessage = nil
                }
            }
        }
    }

    private func handleSendToDisplay() {
        isSending = true
        errorMessage = nil
        successMessage = nil

        Self.logger.debug("Sending to display: \(self.selectedDisplay.name)")

        // Simulate send operation - in real implementation would call FTDisplayClient
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            isSending = false
            successMessage = "Sent to \(self.selectedDisplay.name)"
            Self.logger.info("Send to display completed")

            // Clear success message after 3 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                withAnimation {
                    successMessage = nil
                }
            }
        }
    }
}

#Preview {
    let sampleVariant = Variant(
        targetWidth: 32,
        targetHeight: 32,
        pixelGridData: PixelGrid(width: 32, height: 32).toRGBA8888()
    )

    NavigationStack {
        VariantDetailView(variant: sampleVariant, coordinator: GalleryCoordinator())
    }
}
