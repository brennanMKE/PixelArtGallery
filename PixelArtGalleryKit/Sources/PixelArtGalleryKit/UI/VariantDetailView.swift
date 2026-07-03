import SwiftData
import SwiftUI

/// Shows details of a single variant: a pixel preview, export, and send-to-display.
struct VariantDetailView: View {
    let variant: Variant
    let coordinator: GalleryCoordinator

    @Environment(\.dismiss) private var dismiss

    /// Live list of persisted displays to send to.
    @Query(sort: \FlaschenTaschenDisplay.displayName) private var displays: [FlaschenTaschenDisplay]

    @State private var selectedDisplayID: UUID?
    @State private var isSending = false
    @State private var showExportPicker = false
    @State private var isEditingDimensions = false
    @State private var isConfirmingDelete = false
    @State private var successMessage: String?
    @State private var errorMessage: String?

    /// The currently selected display resolved from `selectedDisplayID`.
    private var selectedDisplay: FlaschenTaschenDisplay? {
        displays.first { $0.id == selectedDisplayID }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.l) {
                infoCard
                previewSection
                exportSection
                sendSection

                if let successMessage {
                    StatusBanner(kind: .success, message: successMessage)
                }
                if let errorMessage {
                    StatusBanner(kind: .error, message: errorMessage)
                }
            }
            .padding()
            .animation(.default, value: successMessage)
            .animation(.default, value: errorMessage)
        }
        .navigationTitle("Variant Details")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        isEditingDimensions = true
                    } label: {
                        Label("Edit Dimensions", systemImage: "ruler")
                    }
                    Button {
                        _ = try? coordinator.duplicateVariant(variant)
                    } label: {
                        Label("Duplicate", systemImage: "plus.square.on.square")
                    }
                    Button(role: .destructive) {
                        isConfirmingDelete = true
                    } label: {
                        Label("Delete Variant", systemImage: "trash")
                    }
                } label: {
                    Label("Actions", systemImage: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showExportPicker) {
            ExportPickerView(
                variant: variant,
                onExport: { format, url in handleExport(format: format, url: url) },
                onCancel: { showExportPicker = false }
            )
        }
        .sheet(isPresented: $isEditingDimensions) {
            VariantEditDimensionsView(
                width: variant.targetWidth,
                height: variant.targetHeight
            ) { width, height in
                try? await coordinator.updateVariantDimensions(variant, width: width, height: height)
            }
        }
        .confirmationDialog(
            "Delete this variant?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete Variant", role: .destructive) {
                coordinator.deleteVariant(variant)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(variant.targetWidth)×\(variant.targetHeight) — this can't be undone.")
        }
    }

    // MARK: - Sections

    private var infoCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("Dimensions")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(variant.targetWidth)×\(variant.targetHeight) px")
                    .font(.headline)
                    .monospacedDigit()
            }
            Spacer()
            VStack(alignment: .trailing, spacing: Theme.Spacing.xs) {
                Text("Created")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(variant.createdDate, style: .date)
                    .font(.headline)
            }
        }
        .card()
    }

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            SectionHeader("Preview")
            PixelGridView(variant: variant)
                .frame(height: 340)
                .card(padding: 0)
        }
    }

    private var exportSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeader("Export")
            Button {
                showExportPicker = true
            } label: {
                Label("Export Variant", systemImage: "arrow.down.doc.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isSending)
        }
    }

    private var sendSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeader("Send to Display")

            if displays.isEmpty {
                InfoRow("No displays yet. Add one from the Displays screen to send variants.", icon: "display")
            } else {
                Picker("Display", selection: $selectedDisplayID) {
                    ForEach(displays) { display in
                        Text("\(display.displayName) (\(display.resolution))")
                            .tag(Optional(display.id))
                    }
                }

                Button(action: handleSendToDisplay) {
                    Label(isSending ? "Sending…" : "Send Now", systemImage: "arrow.up.right.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isSending || selectedDisplay == nil)
            }
        }
        .onChange(of: displays.map(\.id)) { _, ids in
            // Keep a valid selection as the registry changes.
            if selectedDisplayID == nil || !ids.contains(where: { $0 == selectedDisplayID }) {
                selectedDisplayID = ids.first
            }
        }
    }

    // MARK: - Actions

    /// Called by `ExportPickerView` after it has already written the file to `url`.
    private func handleExport(format: String, url: URL) {
        variant.exportFormat = format
        showExportPicker = false
        AppLog.export.info("Export completed successfully: \(format, privacy: .public) -> \(url.lastPathComponent, privacy: .public)")
        flashSuccess("Exported \(format) to \(url.lastPathComponent)")
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

        AppLog.ftDiscovery.debug("Sending to display: \(displayName, privacy: .public) at \(host, privacy: .public):\(port)")

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
                AppLog.ftDiscovery.info("Send to display completed")
                flashSuccess("Sent to \(displayName)")
            } catch {
                isSending = false
                let message = (error as? FTDisplayError)?.errorDescription ?? error.localizedDescription
                AppLog.ftDiscovery.error("Send to display failed: \(error.localizedDescription, privacy: .public)")
                flashError(message)
            }
        }
    }

    /// Show a transient success banner (auto-clears after a few seconds).
    private func flashSuccess(_ message: String) {
        errorMessage = nil
        successMessage = message
        Task {
            try? await Task.sleep(for: .seconds(3))
            if successMessage == message { successMessage = nil }
        }
    }

    /// Show a transient error banner (auto-clears after a few seconds).
    private func flashError(_ message: String) {
        successMessage = nil
        errorMessage = message
        Task {
            try? await Task.sleep(for: .seconds(6))
            if errorMessage == message { errorMessage = nil }
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
