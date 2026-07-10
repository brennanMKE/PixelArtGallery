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
    /// Paint offsets for the current send, seeded from the selected display's
    /// stored defaults (#0056).
    @State private var sendOffsetX: Int = 0
    @State private var sendOffsetY: Int = 0
    @State private var isSending = false
    /// The in-flight send, retained so the user can cancel it by tapping Stop (#0050).
    @State private var sendTask: Task<Void, Never>?
    /// Parameters of the active send, captured at start so stopping can clear the
    /// exact layer/offset/endpoint that was painted — even if the picker or
    /// offset fields changed mid-send (#0053, extended for x/y offsets in #0056).
    @State private var activeSend: ActiveSend?

    /// The endpoint + geometry + layer + offset of an in-flight continuous send.
    private struct ActiveSend: Sendable {
        let host: String
        let port: Int
        let width: Int
        let height: Int
        let scaleFactor: Double
        let layer: Int
        let offsetX: Int
        let offsetY: Int
    }
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
        .onDisappear {
            // Leaving the view stops a continuous send (#0052) so it doesn't keep
            // pushing frames in the background on Mac or iPhone, and clears the
            // painted layer with a final black frame (#0053). Sheets presented over
            // this view don't trigger onDisappear, so opening export/edit won't
            // stop a send. The clear runs detached, so it survives view teardown.
            stopSending()
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

                Stepper(value: $sendOffsetX, in: offsetXRange) {
                    HStack {
                        Text("X Offset")
                        Spacer()
                        Text("\(sendOffsetX)")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(isSending || selectedDisplay == nil)

                Stepper(value: $sendOffsetY, in: offsetYRange) {
                    HStack {
                        Text("Y Offset")
                        Spacer()
                        Text("\(sendOffsetY)")
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
        .onChange(of: displays.map { "\($0.id)|\($0.displayWidth)x\($0.displayHeight)" }, initial: true) { _, _ in
            // Initialize the selection when the view appears (initial: true)
            // and keep it valid as the registry changes.
            updateSelectedDisplay()
            seedSendDefaults()
        }
        .onChange(of: variant.targetWidth) {
            updateSelectedDisplay()
        }
        .onChange(of: variant.targetHeight) {
            updateSelectedDisplay()
        }
        .onChange(of: selectedDisplayID) {
            // Reseed layer + offsets from each newly selected display's defaults.
            seedSendDefaults()
        }
    }

    /// Valid range for the X offset stepper: `0` up to the selected display's
    /// width (exclusive of the last column so the offset can't push the whole
    /// frame off-display). Collapses to `0...0` with no display selected.
    private var offsetXRange: ClosedRange<Int> {
        guard let display = selectedDisplay, display.displayWidth > 1 else { return 0...0 }
        return 0...(display.displayWidth - 1)
    }

    /// Valid range for the Y offset stepper, mirroring ``offsetXRange``.
    private var offsetYRange: ClosedRange<Int> {
        guard let display = selectedDisplay, display.displayHeight > 1 else { return 0...0 }
        return 0...(display.displayHeight - 1)
    }

    /// Auto-select the display whose geometry matches this variant's
    /// dimensions (#0055), falling back to the #0032 rule (keep a still-valid
    /// current, else the default display, else the first) when none match.
    private func updateSelectedDisplay() {
        selectedDisplayID = FlaschenTaschenDisplay.preferredSelection(
            current: selectedDisplayID,
            variantWidth: variant.targetWidth,
            variantHeight: variant.targetHeight,
            among: displays.map { (id: $0.id, source: $0.source, width: $0.displayWidth, height: $0.displayHeight) }
        )
    }

    /// Seed the send layer and x/y offsets from the selected display's
    /// configured defaults (#0047, extended for offsets in #0056). Layer is
    /// clamped into the valid 1…15 range; offsets are clamped non-negative and
    /// further bounded to this display's stepper range so a stored default
    /// that exceeds the display's current geometry doesn't leave the stepper
    /// showing an out-of-range value.
    private func seedSendDefaults() {
        guard let display = selectedDisplay else { return }
        sendLayer = FlaschenTaschenDisplay.clampedLayer(display.layer)
        sendOffsetX = min(FlaschenTaschenDisplay.clampedOffset(display.offsetX), offsetXRange.upperBound)
        sendOffsetY = min(FlaschenTaschenDisplay.clampedOffset(display.offsetY), offsetYRange.upperBound)
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
        // Tapping while sending stops the continuous send (#0050) and clears the
        // layer (#0053).
        if isSending {
            AppLog.ftDiscovery.info("User requested stop of continuous send")
            stopSending()
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
        // Clamp defensively so the send never carries layer 0, an out-of-range
        // layer, or a negative offset, whatever state the controls are in
        // (#0047, extended for offsets in #0056).
        let layer = FlaschenTaschenDisplay.clampedLayer(sendLayer)
        let offsetX = FlaschenTaschenDisplay.clampedOffset(sendOffsetX)
        let offsetY = FlaschenTaschenDisplay.clampedOffset(sendOffsetY)

        // Capture the send parameters so stopSending() can clear this exact
        // endpoint/layer/offset later, independent of any later UI changes (#0053, #0056).
        activeSend = ActiveSend(
            host: host, port: port, width: width, height: height,
            scaleFactor: scaleFactor, layer: layer, offsetX: offsetX, offsetY: offsetY
        )

        isSending = true
        errorMessage = nil
        successMessage = nil
        infoMessage = nil

        AppLog.ftDiscovery.info("Starting continuous send to \(displayName, privacy: .public) at \(host, privacy: .public):\(port) on layer \(layer)")

        sendTask = Task {
            defer {
                isSending = false
                sendTask = nil
                // Clear the captured params on any loop end (including a network
                // error that wasn't a user stop) so a later onDisappear doesn't
                // fire a spurious clear (#0053).
                activeSend = nil
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
                        offset: (x: offsetX, y: offsetY, z: layer)
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

    /// Stop the continuous send and clear the painted layer.
    ///
    /// Cancels the refresh loop, then sends a final all-black frame to the exact
    /// endpoint/layer that was being painted. FlaschenTaschen treats black on any
    /// layer above the background as transparent, so this erases the overlay
    /// immediately instead of waiting for the server's layer timeout (#0053). The
    /// clear runs in a detached task so it completes even as the view is torn down
    /// (#0052) and isn't killed by the loop's cancellation.
    private func stopSending() {
        // Capture before cancelling — the loop's `defer` also nils this out.
        let clearTarget = activeSend
        sendTask?.cancel()
        sendTask = nil
        isSending = false
        activeSend = nil

        guard let target = clearTarget else { return }
        Task.detached {
            let client = FTDisplayClient()
            // All-zero RGBA → RGB (0,0,0); on layers 1–15 the FT server composites
            // black as transparent, erasing this layer.
            let blackFrame = Data(count: target.width * target.height * 4)
            // UDP is lossy; resend a few times as a best-effort erase.
            for _ in 0..<3 {
                try? await client.send(
                    width: target.width,
                    height: target.height,
                    pixelGridData: blackFrame,
                    scaleFactor: target.scaleFactor,
                    to: target.host,
                    port: target.port,
                    offset: (x: target.offsetX, y: target.offsetY, z: target.layer)
                )
                try? await Task.sleep(for: .milliseconds(120))
            }
            AppLog.ftDiscovery.info("Cleared FT layer \(target.layer) on \(target.host, privacy: .public):\(target.port)")
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
