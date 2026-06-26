import SwiftUI
#if os(macOS)
import AppKit
import UniformTypeIdentifiers
#endif

/// View for exporting pixel art variants with format selection and file location picker
struct ExportPickerView: View {
    let variant: Variant
    let onExport: (String, URL) -> Void
    let onCancel: () -> Void

    private let exporter = VariantExporter()
    #if os(iOS)
    private let photoLibrarySaver = PhotoLibrarySaver()
    #endif

    @State private var selectedFormat = "PNG"
    @State private var isExporting = false
    @State private var exportError: String?
    #if os(macOS)
    @State private var selectedFileURL: URL?
    #endif
    #if os(iOS)
    @State private var documentExportURL: IdentifiableURL?
    #endif

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
                Text("Variant: \(variant.targetWidth)×\(variant.targetHeight)")
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

            #if os(macOS)
            // File location info (macOS uses an explicit save-panel location)
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
            #else
            // iOS routes to Photos (raster) or the Files document picker — no file path to show.
            VStack(alignment: .leading, spacing: 8) {
                Text("Save Destination")
                    .font(.headline)
                Text(canSaveToPhotos
                     ? "Save to Photos or export the file via the Files app."
                     : "\(selectedFormat) is not an image — export the file via the Files app.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            #endif

            Spacer()

            // Action buttons
            #if os(macOS)
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
            #else
            VStack(spacing: 12) {
                if canSaveToPhotos {
                    Button(action: saveToPhotos) {
                        HStack {
                            if isExporting {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Saving...")
                            } else {
                                Image(systemName: "photo")
                                Text("Save to Photos")
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isExporting)
                }

                let filesButton = Button(action: saveToFiles) {
                    HStack {
                        if isExporting {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Preparing...")
                        } else {
                            Image(systemName: "folder")
                            Text("Save to Files")
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .disabled(isExporting)

                // Promote the Files button to primary when Photos isn't an option.
                if canSaveToPhotos {
                    filesButton.buttonStyle(.bordered)
                } else {
                    filesButton.buttonStyle(.borderedProminent)
                }

                Button("Cancel") {
                    onCancel()
                }
                .frame(maxWidth: .infinity)
                .buttonStyle(.bordered)
                .disabled(isExporting)
            }
            #endif

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
        #if os(iOS)
        .sheet(item: $documentExportURL) { wrapper in
            DocumentExporterView(
                fileURL: wrapper.url,
                onComplete: { savedURL in
                    documentExportURL = nil
                    AppLog.export.info("Export saved to Files: \(savedURL.lastPathComponent, privacy: .public)")
                    onExport(selectedFormat, savedURL)
                },
                onCancel: {
                    documentExportURL = nil
                }
            )
        }
        #endif
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

    #if os(macOS)
    private func showSavePanel() {
        DispatchQueue.main.async {
            let panel = NSSavePanel()
            panel.allowedContentTypes = [uniformTypeForFormat()]
            panel.nameFieldStringValue = "variant-\(variant.id.uuidString.prefix(8)).\(fileExtension)"
            panel.message = "Choose a location to save your pixelated image"

            panel.begin { response in
                if response == .OK, let url = panel.url {
                    selectedFileURL = url
                    AppLog.export.debug("User selected save location: \(url.path, privacy: .public)")
                }
            }
        }
    }
    #endif

    #if os(iOS)
    /// Whether the currently selected format is a raster image eligible for the Photos library.
    private var canSaveToPhotos: Bool {
        guard let format = ExportFormat(name: selectedFormat) else { return false }
        return PhotoLibrarySaver.canSaveToPhotos(format)
    }

    private var temporaryExportURL: URL {
        let name = "variant-\(variant.id.uuidString.prefix(8)).\(fileExtension)"
        return FileManager.default.temporaryDirectory.appendingPathComponent(name)
    }

    /// Encode the variant to a temp file via `VariantExporter` (off the main actor) and return
    /// its URL. Throws the same `ExportError`s the export path surfaces.
    private func exportToTemporaryFile(format: ExportFormat) async throws -> URL {
        let url = temporaryExportURL
        let exporter = self.exporter
        let width = variant.targetWidth
        let height = variant.targetHeight
        let pixelData = variant.pixelGridData
        let scaleFactor = variant.scaleFactor

        try await Task.detached {
            try exporter.export(
                width: width,
                height: height,
                pixelGridData: pixelData,
                scaleFactor: scaleFactor,
                as: format,
                to: url
            )
        }.value
        return url
    }

    /// Encode the variant and add it to the Photos library, reporting success/failure.
    private func saveToPhotos() {
        guard let format = ExportFormat(name: selectedFormat) else {
            exportError = "Unsupported format: \(selectedFormat)"
            return
        }

        isExporting = true
        exportError = nil

        Task {
            do {
                let url = try await exportToTemporaryFile(format: format)
                try await photoLibrarySaver.saveToPhotos(fileURL: url, format: format)
                try? FileManager.default.removeItem(at: url)
                isExporting = false
                AppLog.export.info("Saved \(self.selectedFormat, privacy: .public) to Photos library")
                onExport(selectedFormat, url)
            } catch {
                isExporting = false
                let message = describeSaveError(error)
                exportError = message
                AppLog.export.error("Save to Photos failed: \(message, privacy: .public)")
            }
        }
    }

    /// Encode the variant to a temp file and present the Files document picker over it.
    private func saveToFiles() {
        guard let format = ExportFormat(name: selectedFormat) else {
            exportError = "Unsupported format: \(selectedFormat)"
            return
        }

        isExporting = true
        exportError = nil

        Task {
            do {
                let url = try await exportToTemporaryFile(format: format)
                isExporting = false
                documentExportURL = IdentifiableURL(url: url)
            } catch {
                isExporting = false
                let message = describeSaveError(error)
                exportError = message
                AppLog.export.error("Save to Files failed: \(message, privacy: .public)")
            }
        }
    }

    private func describeSaveError(_ error: Error) -> String {
        if let exportError = error as? ExportError {
            return Self.describe(exportError)
        }
        if let photoError = error as? PhotoLibrarySaveError {
            switch photoError {
            case .unsupportedFormat(let format):
                return "\(format) is not an image and cannot be saved to Photos."
            case .notAuthorized:
                return "Photos access was denied. Enable it in Settings to save images."
            case .saveFailed(let underlying):
                return "Could not save to Photos: \(underlying)"
            case .unavailable:
                return "Saving to Photos is not available on this device."
            }
        }
        return error.localizedDescription
    }
    #endif

    #if os(macOS)
    private func performExport() {
        guard let fileURL = selectedFileURL else {
            exportError = "Please select a save location"
            return
        }
        guard let format = ExportFormat(name: selectedFormat) else {
            exportError = "Unsupported format: \(selectedFormat)"
            return
        }

        isExporting = true
        exportError = nil

        AppLog.export.debug("Exporting variant \(self.variant.id) as \(self.selectedFormat, privacy: .public) to \(fileURL.path, privacy: .public)")

        // The exporter is nonisolated and pure; encode the file bytes off the main actor
        // by reading the variant's plain fields first (Variant is @Model / main-actor bound,
        // so it cannot itself cross actor boundaries).
        let exporter = self.exporter
        let width = variant.targetWidth
        let height = variant.targetHeight
        let pixelData = variant.pixelGridData
        let scaleFactor = variant.scaleFactor

        Task {
            do {
                try await Task.detached {
                    try exporter.export(
                        width: width,
                        height: height,
                        pixelGridData: pixelData,
                        scaleFactor: scaleFactor,
                        as: format,
                        to: fileURL
                    )
                }.value
                isExporting = false
                AppLog.export.info("Export completed: \(self.selectedFormat, privacy: .public)")
                onExport(selectedFormat, fileURL)
            } catch {
                isExporting = false
                let message = (error as? ExportError).map(Self.describe) ?? error.localizedDescription
                exportError = message
                AppLog.export.error("Export failed: \(message, privacy: .public)")
            }
        }
    }
    #endif

    private static func describe(_ error: ExportError) -> String {
        switch error {
        case .invalidPixelData(let expected, let actual):
            return "Invalid pixel data (expected \(expected) bytes, got \(actual))."
        case .invalidDimensions(let width, let height):
            return "Invalid dimensions (\(width)×\(height))."
        case .imageCreationFailed:
            return "Could not create the image."
        case .encodingFailed(let format):
            return "Could not encode \(format)."
        case .serializationFailed:
            return "Could not serialize the color matrix."
        case .writeFailed(let underlying):
            return "Could not write the file: \(underlying)"
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

#if os(iOS)
/// Wraps a `URL` so it can drive a `.sheet(item:)` presentation (URL is not `Identifiable`).
private struct IdentifiableURL: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}
#endif

#Preview {
    let sampleVariant = Variant(
        targetWidth: 32,
        targetHeight: 32,
        pixelGridData: PixelGrid(width: 32, height: 32).toRGBA8888()
    )

    ExportPickerView(
        variant: sampleVariant,
        onExport: { format, url in
            print("Export \(format) to \(url)")
        },
        onCancel: {
            print("Export cancelled")
        }
    )
}
