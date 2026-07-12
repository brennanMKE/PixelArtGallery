import SwiftData
import SwiftUI

/// Shows details of a single variant: a pixel preview, export, and send-to-display.
struct VariantDetailView: View {
    let variant: Variant
    let coordinator: GalleryCoordinator

    @Environment(\.dismiss) private var dismiss

    /// Live list of persisted displays to send to.
    @Query(sort: \FlaschenTaschenDisplay.displayName) private var displays: [FlaschenTaschenDisplay]

    /// The display a display-first push (#0064) wants the send offset
    /// centered on, or `nil` for the ordinary variant-list entry point. Set
    /// once at init; stays set (and reapplies the centered offset on every
    /// reseed) for as long as `selectedDisplayID` keeps matching it, and is
    /// cleared for good the moment the selection moves to a *different*
    /// display — see ``SendDefaultsSeed`` for why "stays set until the
    /// selection diverges" (rather than "cleared on first use") is what makes
    /// this survive SwiftUI's redundant first-appearance reseed.
    @State private var pendingCenteredDisplayID: UUID?

    @State private var selectedDisplayID: UUID?
    @State private var sendLayer: Int = FlaschenTaschenDisplay.defaultLayer
    /// Paint offsets for the current send, seeded from the selected display's
    /// stored defaults (#0056).
    @State private var sendOffsetX: Int = 0
    @State private var sendOffsetY: Int = 0
    /// Whether the next send converts the variant's pixels to grayscale
    /// (#0077) — transient, per-send state like layer/offset, no stored
    /// default in v1. Applied once at payload-build time in
    /// ``handleSendToDisplay()``; frozen for the duration of a send.
    @State private var sendGrayscale = false
    /// Whether the "Advanced" section (x/y offsets + grayscale) is expanded.
    /// Collapsed by default — these are fine-tuning controls, unlike Layer
    /// which stays a primary control next to Send.
    @State private var isAdvancedExpanded = false
    /// The continuous-send loop, extracted to ``FTSendController`` (#0067) so
    /// the same loop (cancellation, mid-send clear-on-change, the #0053
    /// stop-clear) is shared with the send popover's transient-preview send
    /// instead of duplicated.
    @State private var sendController = FTSendController()
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

    /// Whether a continuous send is currently in flight — forwarded from
    /// ``FTSendController`` so the rest of this view's UI logic (banners,
    /// disabling the display picker, the Send/Stop button label) is
    /// unchanged by the #0067 extraction.
    private var isSending: Bool { sendController.isSending }

    /// - Parameter centerOnDisplayID: When arriving from the display-first
    ///   picker (#0064), the id of the display the send offset should be
    ///   seeded to the aspect-fit centered value for, instead of that
    ///   display's stored defaults. Defaults to `nil` so every existing call
    ///   site (opening a variant from the variant list) compiles unchanged and
    ///   keeps today's stored-defaults seeding behavior.
    init(variant: Variant, coordinator: GalleryCoordinator, centerOnDisplayID: UUID? = nil) {
        self.variant = variant
        self.coordinator = coordinator
        _pendingCenteredDisplayID = State(initialValue: centerOnDisplayID)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.l) {
                infoCard

                // Sending is the primary reason to open a variant, so the send
                // controls (and their status banners) sit right after the info
                // card — visible without scrolling on both platforms (#0057).
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

                previewSection
                exportSection
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
            sendController.stop()
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
            PixelGridView(variant: variant, coordinator: coordinator)
                .frame(height: 420)
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
                // Locked while sending: the endpoint is captured at the start
                // of a send, so switching displays mid-send would desync the
                // picker from where frames are actually going (#0053, #0057).
                Picker("Display", selection: $selectedDisplayID) {
                    ForEach(displays) { display in
                        Text("\(display.displayName) (\(display.resolution))")
                            .tag(Optional(display.id))
                    }
                }
                .disabled(isSending)

                // Layer stays editable during an active send (#0057) — the
                // send loop reads it live each frame, so a change here takes
                // effect on the next frame without stopping the send. Kept as
                // a primary control next to Send (it's the routinely adjusted
                // FT z-plane); x/y offsets and grayscale live under Advanced
                // below. Only the display picker is locked while sending.
                Stepper(value: $sendLayer, in: FlaschenTaschenDisplay.layerRange) {
                    HStack {
                        Text("Layer")
                        Spacer()
                        Text("\(sendLayer)")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(selectedDisplay == nil)

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

                // Fine-tuning controls, collapsed by default (#0077). X/Y stay
                // live-editable during an active send (#0057) — moving them
                // here changes layout only, not their binding or disabled
                // rules. Grayscale is disabled while sending because the
                // payload's pixel data is frozen at send start, so a mid-send
                // toggle would silently do nothing until the next send.
                DisclosureGroup("Advanced", isExpanded: $isAdvancedExpanded) {
                    Stepper(value: $sendOffsetX, in: offsetXRange) {
                        HStack {
                            Text("X Offset")
                            Spacer()
                            Text("\(sendOffsetX)")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                    .disabled(selectedDisplay == nil)

                    Stepper(value: $sendOffsetY, in: offsetYRange) {
                        HStack {
                            Text("Y Offset")
                            Spacer()
                            Text("\(sendOffsetY)")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                    .disabled(selectedDisplay == nil)

                    Toggle("Grayscale", isOn: $sendGrayscale)
                        .disabled(selectedDisplay == nil || isSending)
                }
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

    /// Valid range for the X offset stepper: `0` up to `displayWidth -
    /// variant.targetWidth` (#0064), so a nudge can never push the image
    /// past the display's trailing edge. Collapses to `0...0` with no display
    /// selected, or when the variant is already as wide as (or wider than)
    /// the display.
    private var offsetXRange: ClosedRange<Int> {
        guard let display = selectedDisplay else { return 0...0 }
        return FlaschenTaschenDisplay.offsetRange(
            displayDimension: display.displayWidth, imageDimension: variant.targetWidth
        )
    }

    /// Valid range for the Y offset stepper, mirroring ``offsetXRange``.
    private var offsetYRange: ClosedRange<Int> {
        guard let display = selectedDisplay else { return 0...0 }
        return FlaschenTaschenDisplay.offsetRange(
            displayDimension: display.displayHeight, imageDimension: variant.targetHeight
        )
    }

    /// Auto-select the display whose geometry matches this variant's
    /// dimensions (#0055), falling back to the #0032 rule (keep a still-valid
    /// current, else the default display, else the first) when none match.
    ///
    /// A pending display-first push (#0064) takes priority over both: a
    /// letterboxed fitted variant's dimensions don't equal the display's own
    /// dimensions, so the #0055 geometry match would not otherwise pick the
    /// display the user just chose.
    private func updateSelectedDisplay() {
        if let pendingCenteredDisplayID, displays.contains(where: { $0.id == pendingCenteredDisplayID }) {
            selectedDisplayID = pendingCenteredDisplayID
            return
        }

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
    ///
    /// Exception (#0064): when this seed matches the pending display-first
    /// push's display, the x/y offsets are instead seeded to the aspect-fit
    /// centering offset for this variant on that display — not the display's
    /// stored defaults. The layer still seeds from the display's stored
    /// default in both cases.
    ///
    /// The actual decision is delegated to ``SendDefaultsSeed/seed(_:)``, a
    /// pure function, so it can be unit-tested directly. This view is called
    /// (redundantly, by design) both right after `updateSelectedDisplay()`
    /// changes `selectedDisplayID` and again from the separate
    /// `onChange(of: selectedDisplayID)` reacting to that same change —
    /// `SendDefaultsSeed.seed(_:)` is idempotent under that repetition (see
    /// its doc comment for why a naive "clear pending on first use" approach
    /// let the second call clobber the centered seed with stored defaults,
    /// the #0064 review bounce).
    private func seedSendDefaults() {
        guard let display = selectedDisplay else { return }

        let output = SendDefaultsSeed.seed(
            SendDefaultsSeed.Input(
                pendingCenteredDisplayID: pendingCenteredDisplayID,
                selectedDisplayID: selectedDisplayID,
                variantWidth: variant.targetWidth,
                variantHeight: variant.targetHeight,
                displayWidth: display.displayWidth,
                displayHeight: display.displayHeight,
                displayLayer: display.layer,
                displayOffsetX: display.offsetX,
                displayOffsetY: display.offsetY
            )
        )

        sendLayer = output.layer
        sendOffsetX = output.offsetX
        sendOffsetY = output.offsetY
        pendingCenteredDisplayID = output.pendingCenteredDisplayID
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
        // Tapping while sending stops the continuous send (#0050) and clears the
        // layer (#0053).
        if sendController.isSending {
            AppLog.ftDiscovery.info("User requested stop of continuous send")
            sendController.stop()
            return
        }

        guard let display = selectedDisplay else { return }

        // Read the @Model's plain fields on the main actor before handing the
        // value-typed payload to the off-main-actor client. The endpoint and
        // the variant's geometry never change once a send starts — only
        // layer/x/y are read live, each frame, via `frameOffset` below (#0057).
        let displayName = display.displayName
        // Grayscale is a static transform of the frozen pixel data, applied
        // once here at send start (#0077) — same contract as #0057's
        // "endpoint + pixel data frozen, only layer/x/y read live per frame."
        let payload = FTSendPayload(
            host: display.host,
            port: display.port,
            width: variant.targetWidth,
            height: variant.targetHeight,
            pixelGridData: sendGrayscale
                ? PixelGrid.grayscale(rgba8888: variant.pixelGridData)
                : variant.pixelGridData,
            scaleFactor: variant.scaleFactor
        )

        errorMessage = nil
        successMessage = nil
        infoMessage = nil

        AppLog.ftDiscovery.info("Starting continuous send to \(displayName, privacy: .public) at \(payload.host, privacy: .public):\(payload.port)")

        sendController.start(
            payload: payload,
            frameOffset: {
                // Read live each frame — this is what makes layer/x/y stay
                // editable during a send (#0057). No capture list: this
                // closure reads `self.sendLayer`/`sendOffsetX`/`sendOffsetY`
                // through their `@State` storage, not a value snapshotted at
                // send-start.
                (layer: sendLayer, offsetX: sendOffsetX, offsetY: sendOffsetY)
            },
            onError: { message in
                flashError(message)
            },
            onStopped: { _ in
                flashInfo("Stopped sending to \(displayName)")
            }
        )
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
