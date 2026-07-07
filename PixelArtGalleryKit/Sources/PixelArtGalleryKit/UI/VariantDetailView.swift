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
    @State private var sendLayer: Int = FlaschenTaschenDisplay.defaultLayer
    @State private var isSending = false
    /// The in-flight send, retained so the user can cancel it by tapping Stop (#0050).
    @State private var sendTask: Task<Void, Never>?
    @State private var showExportPicker = false
    @State private var isEditingDimensions = false
    @State private var isConfirmingDelete = false
    @State private var successMessage: String?
    @State private var errorMessage: String?
    @State private var infoMessage: String?

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

                if isSending {
                    StatusBanner(
                        kind: .info,
                        message: "Sending to \(selectedDisplay?.displayName ?? "display")… Tap Stop Sending to end."
                    )
                }
                if let successMessage {
                    StatusBanner(kind: .success, message: successMessage)
                }
                if let errorMessage {
                    StatusBanner(kind: .error, message: errorMessage)
                }
                if let infoMessage {
                    StatusBanner(kind: .info, message: infoMessage)
                }
            }
            .padding()
            .animation(.default, value: isSending)
            .animation(.default, value: successMessage)
            .animation(.default, value: errorMessage)
            .animation(.default, value: infoMessage)
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

                Stepper(value: $sendLayer, in: FlaschenTaschenDisplay.layerRange) {
                    HStack {
                        Text("Layer")
                        Spacer()
                        Text("\(sendLayer)")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(isSending || selectedDisplay == nil)

                // Stays tappable while sending so the user can stop an in-flight
                // (or stuck) send by tapping again (#0050).
                Button(action: handleSendToDisplay) {
                    Label(
                        isSending ? "Stop Sending" : "Send Now",
                        systemImage: isSending ? "stop.circle.fill" : "arrow.up.right.circle.fill"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(isSending ? .red : nil)
                .controlSize(.large)
                .disabled(selectedDisplay == nil)
            }
        }
        .onChange(of: displays.map(\.id), initial: true) { _, _ in
            // Initialize the selection when the view appears (initial: true)
            // and keep it valid as the registry changes: prefer the default
            // display, else the first, but never stomp a still-valid explicit
            // choice (#0032).
            selectedDisplayID = FlaschenTaschenDisplay.preferredSelection(
                current: selectedDisplayID,
                among: displays.map { (id: $0.id, source: $0.source) }
            )
            seedSendLayer()
        }
        .onChange(of: selectedDisplayID) {
            // Reseed the layer from each newly selected display's default.
            seedSendLayer()
        }
    }

    /// Seed the send layer from the selected display's configured default,
    /// clamped into the valid 1…15 range (#0047).
    private func seedSendLayer() {
        guard let display = selectedDisplay else { return }
        sendLayer = FlaschenTaschenDisplay.clampedLayer(display.layer)
    }

    // MARK: - Actions

    /// Called by `ExportPickerView` after it has already written the file to `url`.
    private func handleExport(format: String, url: URL) {
        variant.exportFormat = format
        showExportPicker = false
        AppLog.export.info("Export completed successfully: \(format, privacy: .public) -> \(url.lastPathComponent, privacy: .public)")
        flashSuccess("Exported \(format) to \(url.lastPathComponent)")
    }

    /// How often the continuous send re-pushes the frame to the display. FT
    /// servers drop a layer after their layer-timeout (commonly ~15s) if it
    /// isn't refreshed, so we resend well inside that window to keep the image up.
    private static let sendRefreshInterval: Duration = .seconds(2)

    private func handleSendToDisplay() {
        // Tapping while sending stops the continuous send (#0050). Cancellation is
        // cooperative: cancelling the task ends the refresh loop and the client
        // aborts any in-flight packet.
        if isSending {
            AppLog.ftDiscovery.info("User requested stop of continuous send")
            sendTask?.cancel()
            return
        }

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
        // Clamp defensively so the send never carries layer 0 or an out-of-range
        // value, whatever state the stepper is in (#0047).
        let layer = FlaschenTaschenDisplay.clampedLayer(sendLayer)

        isSending = true
        errorMessage = nil
        successMessage = nil
        infoMessage = nil

        AppLog.ftDiscovery.info("Starting continuous send to \(displayName, privacy: .public) at \(host, privacy: .public):\(port) on layer \(layer)")

        sendTask = Task {
            defer {
                isSending = false
                sendTask = nil
            }
            let client = FTDisplayClient()
            var frameCount = 0
            do {
                // Keep pushing the frame until the user taps Stop (task cancelled).
                while !Task.isCancelled {
                    try await client.send(
                        width: width,
                        height: height,
                        pixelGridData: pixelGridData,
                        scaleFactor: scaleFactor,
                        to: host,
                        port: port,
                        offset: (x: 0, y: 0, z: layer)
                    )
                    frameCount += 1
                    // Sleeping is a cancellation point, so Stop ends the loop promptly.
                    try await Task.sleep(for: Self.sendRefreshInterval)
                }
            } catch let error as FTDisplayError where error == .cancelled {
                // User tapped Stop mid-packet — normal exit, fall through below.
            } catch is CancellationError {
                // User tapped Stop during the inter-frame sleep — normal exit.
            } catch {
                let message = (error as? FTDisplayError)?.errorDescription ?? error.localizedDescription
                AppLog.ftDiscovery.error("Continuous send failed after \(frameCount) frame(s): \(error.localizedDescription, privacy: .public)")
                flashError(message)
                return
            }
            AppLog.ftDiscovery.info("Stopped continuous send to \(displayName, privacy: .public) after \(frameCount) frame(s)")
            flashInfo("Stopped sending to \(displayName)")
        }
    }

    /// Show a transient success banner (auto-clears after a few seconds).
    private func flashSuccess(_ message: String) {
        errorMessage = nil
        infoMessage = nil
        successMessage = message
        Task {
            try? await Task.sleep(for: .seconds(3))
            if successMessage == message { successMessage = nil }
        }
    }

    /// Show a transient error banner (auto-clears after a few seconds).
    private func flashError(_ message: String) {
        successMessage = nil
        infoMessage = nil
        errorMessage = message
        Task {
            try? await Task.sleep(for: .seconds(6))
            if errorMessage == message { errorMessage = nil }
        }
    }

    /// Show a transient neutral banner (e.g. a cancelled send).
    private func flashInfo(_ message: String) {
        successMessage = nil
        errorMessage = nil
        infoMessage = message
        Task {
            try? await Task.sleep(for: .seconds(3))
            if infoMessage == message { infoMessage = nil }
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
