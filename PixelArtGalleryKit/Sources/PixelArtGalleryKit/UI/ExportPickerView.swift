import SwiftUI
import os.log
#if os(macOS)
import AppKit
import UniformTypeIdentifiers
#endif

/// View for exporting pixel art variants with format selection and file location picker
struct ExportPickerView: View {
    let variant: MockVariant
    let onExport: (String, URL) -> Void
    let onCancel: () -> Void

    @State private var selectedFormat = "PNG"
    @State private var isShowingSavePanel = false
    @State private var selectedFileURL: URL?
    @State private var isExporting = false
    @State private var exportError: String?

    private static let logger = Logger(subsystem: "com.pixelartgallery.ui", category: "ExportPickerView")

    private var fileExtension: String {
        selectedFormat.lowercased()
    }

    private var mimeType: String {
        switch selectedFormat {
        case "PNG":
            return "image/png"
        case "HEIC":
            return "image/heic"
        case "PPM":
            return "image/x-portable-pixmap"
        case "JSON":
            return "application/json"
        default:
            return "application/octet-stream"
        }
    }

    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                Text("Export Variant")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("Variant: \(variant.width)×\(variant.height)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Format selection
            VStack(alignment: .leading, spacing: 12) {
                Text("Format")
                    .font(.headline)

                Picker("Export Format", selection: $selectedFormat) {
                    Text("PNG").tag("PNG")
                    Text("HEIC").tag("HEIC")
                    Text("PPM").tag("PPM")
                    Text("JSON").tag("JSON")
                }
                .pickerStyle(.segmented)

                // Format description
                Text(formatDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // File location info
            VStack(alignment: .leading, spacing: 8) {
                if let url = selectedFileURL {
                    Text("Save Location")
                        .font(.headline)
                    HStack {
                        Image(systemName: "doc")
                            .foregroundColor(.blue)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(url.lastPathComponent)
                                .font(.caption)
                                .fontWeight(.semibold)
                            Text(url.deletingLastPathComponent().path)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                    }
                    .padding(8)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(6)
                } else {
                    Text("No location selected")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Action buttons
            HStack(spacing: 12) {
                Button("Cancel") {
                    onCancel()
                }
                .frame(maxWidth: .infinity)
                .buttonStyle(.bordered)

                Button(action: showSavePanel) {
                    HStack {
                        Image(systemName: "folder")
                        Text("Choose Location")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(isExporting)

                Button(action: performExport) {
                    if isExporting {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Exporting...")
                        }
                    } else {
                        HStack {
                            Image(systemName: "arrow.down.doc")
                            Text("Export")
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .buttonStyle(.borderedProminent)
                .disabled(isExporting || selectedFileURL == nil)
            }

            // Error message
            if let error = exportError {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundColor(.red)
                        Text("Export Failed")
                            .fontWeight(.semibold)
                    }
                    Text(error)
                        .font(.caption)
                }
                .padding(12)
                .background(Color.red.opacity(0.1))
                .cornerRadius(6)
            }
        }
        .padding()
    }

    private var formatDescription: String {
        switch selectedFormat {
        case "PNG":
            return "Portable Network Graphics - best for web and general use"
        case "HEIC":
            return "High Efficiency Image Container - modern Apple format"
        case "PPM":
            return "Portable Pixmap - raw RGB format for analysis"
        case "JSON":
            return "JSON color matrix - for programmatic processing"
        default:
            return ""
        }
    }

    private func showSavePanel() {
        #if os(macOS)
        DispatchQueue.main.async {
            let panel = NSSavePanel()
            panel.allowedContentTypes = [uniformTypeForFormat()]
            panel.nameFieldStringValue = "variant-\(variant.id).\(fileExtension)"
            panel.message = "Choose a location to save your pixelated image"

            panel.begin { response in
                if response == .OK, let url = panel.url {
                    selectedFileURL = url
                    Self.logger.debug("User selected save location: \(url.path)")
                }
            }
        }
        #else
        // iOS: Use document picker or file export via Files app
        isShowingSavePanel = true
        #endif
    }

    private func performExport() {
        guard let fileURL = selectedFileURL else {
            exportError = "Please select a save location"
            return
        }

        isExporting = true
        exportError = nil

        Self.logger.debug("Exporting variant \(self.variant.id) as \(self.selectedFormat) to \(fileURL.path)")

        // Simulate export delay (in real implementation, this would call VariantExporter)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            isExporting = false
            onExport(selectedFormat, fileURL)
            Self.logger.info("Export completed: \(self.selectedFormat)")
        }
    }

    #if os(macOS)
    private func uniformTypeForFormat() -> UTType {
        switch selectedFormat {
        case "PNG":
            return .png
        case "HEIC":
            return .heic
        case "PPM":
            return UTType(filenameExtension: "ppm") ?? .text
        case "JSON":
            return .json
        default:
            return .data
        }
    }
    #endif
}

#Preview {
    ExportPickerView(
        variant: MockVariant.samples[0],
        onExport: { format, url in
            print("Export \(format) to \(url)")
        },
        onCancel: {
            print("Export cancelled")
        }
    )
}
