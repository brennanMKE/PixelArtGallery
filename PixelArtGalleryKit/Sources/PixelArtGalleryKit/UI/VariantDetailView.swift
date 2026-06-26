import SwiftData
import SwiftUI
import os.log

/// Shows details of a single variant with preview and export options
struct VariantDetailView: View {
    let variant: Variant
    let coordinator: GalleryCoordinator

    /// Live list of persisted displays to send to, replacing the former mock
    /// samples. The actual network send is issue 0012.
    @Query(sort: \FlaschenTaschenDisplay.displayName) private var displays: [FlaschenTaschenDisplay]

    @State private var selectedExportFormat = "PNG"
    @State private var selectedDisplayID: UUID?
    @State private var isExporting = false
    @State private var isSending = false
    @State private var showExportPicker = false
    @State private var successMessage: String?
    @State private var errorMessage: String?

    private static let logger = Logger(subsystem: "com.pixelartgallery.ui", category: "VariantDetailView")

    /// The currently selected display resolved from `selectedDisplayID`.
    private var selectedDisplay: FlaschenTaschenDisplay? {
        displays.first { $0.id == selectedDisplayID }
    }

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
                    ExportPickerView(
                        variant: variant,
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

                    if displays.isEmpty {
                        Text("No displays yet. Add one from the Displays screen to send variants.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Picker("Display", selection: $selectedDisplayID) {
                            ForEach(displays) { display in
                                Text("\(display.displayName) (\(display.resolution))")
                                    .tag(Optional(display.id))
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
                        .disabled(isSending || isExporting || selectedDisplay == nil)
                    }
                }
                .onChange(of: displays.map(\.id)) { _, ids in
                    // Keep a valid selection as the registry changes.
                    if selectedDisplayID == nil || !ids.contains(where: { $0 == selectedDisplayID }) {
                        selectedDisplayID = ids.first
                    }
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

    /// Called by `ExportPickerView` after it has already written the file to `url`.
    /// Records the last-used format on the variant and surfaces a success message.
    private func handleExport(format: String, url: URL) {
        errorMessage = nil
        variant.exportFormat = format
        showExportPicker = false
        successMessage = "Exported \(format) to \(url.lastPathComponent)"
        Self.logger.info("Export completed successfully: \(format) -> \(url.lastPathComponent)")

        // Clear success message after 3 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            withAnimation {
                successMessage = nil
            }
        }
    }

    private func handleSendToDisplay() {
        guard let display = selectedDisplay else { return }

        // Read the @Model's plain fields on the main actor before handing the
        // value-typed payload to the off-main-actor client.
        let displayName = display.displayName
        let host = display.host
        let port = display.port
        let width = variant.targetWidth
        let height = variant.targetHeight
        let pixelGridData = variant.pixelGridData
        let scaleFactor = variant.scaleFactor

        isSending = true
        errorMessage = nil
        successMessage = nil

        Self.logger.debug("Sending to display: \(displayName) at \(host):\(port)")

        Task {
            do {
                let client = FTDisplayClient()
                try await client.send(
                    width: width,
                    height: height,
                    pixelGridData: pixelGridData,
                    scaleFactor: scaleFactor,
                    to: host,
                    port: port
                )
                isSending = false
                successMessage = "Sent to \(displayName)"
                Self.logger.info("Send to display completed")

                // Clear success message after 3 seconds
                try? await Task.sleep(for: .seconds(3))
                withAnimation { successMessage = nil }
            } catch {
                isSending = false
                errorMessage = (error as? FTDisplayError)?.errorDescription ?? error.localizedDescription
                Self.logger.error("Send to display failed: \(error.localizedDescription, privacy: .public)")
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
