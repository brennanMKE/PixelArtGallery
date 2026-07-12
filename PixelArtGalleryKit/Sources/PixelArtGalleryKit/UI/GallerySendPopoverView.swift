import SwiftData
import SwiftUI

/// The full send experience for one gallery item, presented from a grid-cell
/// tap in ``GalleryListView`` (#0067) instead of pushing ``GalleryDetailView``.
///
/// **Presentation.** iPad/macOS get a real `.popover` anchored on the tapped
/// cell; iPhone (compact width) gets `.popover`'s automatic sheet adaptation
/// rather than a forced `.presentationCompactAdaptation(.popover)` — this
/// content is a full send surface (dropdown + preview + Send + a scrollable
/// variants list), and a true anchored popover on an iPhone would be a
/// cramped bubble that clips the list and fights the keyboard. See
/// `GalleryListView`'s `.popover` call site for the presentation modifiers.
///
/// **Contents, top to bottom:** an FT display dropdown defaulting to the
/// last-used display (#0066), the fitted + centered transient preview for
/// the current selection, a Send/Stop button, a Save-as-Variant button, and
/// the item's saved-variants list (each row pushing the existing
/// ``VariantDetailView`` editor). Owns its own `NavigationStack` so that push
/// works from inside the popover/sheet.
struct GallerySendPopoverView: View {
    let item: GalleryItem
    let coordinator: GalleryCoordinator

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    /// Live list of persisted displays for the dropdown.
    @Query(sort: \FlaschenTaschenDisplay.displayName) private var displays: [FlaschenTaschenDisplay]

    @State private var selectedDisplayID: UUID?
    /// The transient fitted preview for the current selection (#0066) —
    /// `nil` while none is selected or a fresh computation is in flight.
    @State private var preview: FittedPreview?
    /// The continuous-send loop, shared with `VariantDetailView` via
    /// ``FTSendController`` (#0067) rather than duplicated.
    @State private var sendController = FTSendController()
    @State private var successMessage: String?
    @State private var errorMessage: String?
    @State private var infoMessage: String?

    /// The currently selected display resolved from `selectedDisplayID`.
    private var selectedDisplay: FlaschenTaschenDisplay? {
        displays.first { $0.id == selectedDisplayID }
    }

    private var isSending: Bool { sendController.isSending }

    var body: some View {
        NavigationStack {
            Group {
                if displays.isEmpty {
                    // No dead popover: offer the same Scan/Add affordances as
                    // Settings' display registry (#0067).
                    DisplayEmptyStateView(coordinator: coordinator)
                } else {
                    content
                }
            }
            .navigationTitle(item.originalName)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            #endif
            .navigationDestination(for: Variant.self) { variant in
                VariantDetailView(variant: variant, coordinator: coordinator)
            }
        }
        #if os(macOS)
        // Popovers on macOS collapse to their content's intrinsic size
        // otherwise; this is a full send surface, not a tiny bubble.
        .frame(minWidth: 360, idealWidth: 400, minHeight: 520, idealHeight: 620)
        #endif
        .onAppear {
            coordinator.configure(modelContext: modelContext)
        }
        .onDisappear {
            // Dismissing mid-send (outside-tap/ESC on macOS, swipe-down on
            // iOS) stops the loop and clears the display — the clear runs
            // detached (#0053), so it survives this view's teardown.
            sendController.stop()
        }
    }

    // MARK: - Populated content

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                displayPicker

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

                previewCanvas
                actionButtons
                variantsList
            }
            .padding()
            .animation(.default, value: isSending)
            .animation(.default, value: successMessage)
            .animation(.default, value: errorMessage)
            .animation(.default, value: infoMessage)
        }
        .onChange(of: displays.map(\.id), initial: true) { _, _ in
            initializeSelectionIfNeeded()
        }
        .onChange(of: selectedDisplayID) { _, newValue in
            guard let newValue, let display = displays.first(where: { $0.id == newValue }) else { return }
            coordinator.rememberLastUsedDisplay(display)
        }
    }

    private var displayPicker: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            SectionHeader("Display")
            Picker("Display", selection: $selectedDisplayID) {
                ForEach(displays) { display in
                    Text("\(display.displayName) (\(display.resolution))")
                        .tag(Optional(display.id))
                }
            }
            .pickerStyle(.menu)
            // Locked while sending: the endpoint is captured at the start of
            // a send, so switching displays mid-send would desync the
            // picker from where frames are actually going (#0053/#0057).
            .disabled(isSending)
        }
    }

    /// The fitted + centered preview, letterboxed inside a display-aspect
    /// black canvas so its placement reads as centered even though the
    /// rendered image itself is simply the fit-sized grid (its offset is
    /// always the centering offset, so plain centering inside the
    /// display-aspect frame is visually exact — no manual positioning math
    /// needed here).
    private var previewCanvas: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            SectionHeader("Preview")
            Color.black
                .aspectRatio(displayAspectRatio, contentMode: .fit)
                .overlay {
                    if let preview {
                        PixelDataImageView(
                            pixelGridData: preview.pixelGridData,
                            width: preview.width,
                            height: preview.height
                        )
                        .padding(Theme.Spacing.xs)
                    } else {
                        ProgressView()
                            .tint(.white)
                    }
                }
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
        .task(id: selectedDisplayID) {
            await loadPreview()
        }
    }

    /// The selected display's aspect ratio for the letterbox canvas, or
    /// square with nothing selected yet.
    private var displayAspectRatio: CGFloat {
        guard let display = selectedDisplay, display.displayHeight > 0 else { return 1 }
        return CGFloat(display.displayWidth) / CGFloat(display.displayHeight)
    }

    private var actionButtons: some View {
        VStack(spacing: Theme.Spacing.m) {
            // Stays tappable while sending so the user can stop an in-flight
            // send by tapping again (#0050).
            Button(action: handleSendToggle) {
                Label(
                    isSending ? "Stop Sending" : "Send Now",
                    systemImage: isSending ? "stop.circle.fill" : "arrow.up.right.circle.fill"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(isSending ? .red : nil)
            .controlSize(.large)
            .disabled(preview == nil && !isSending)

            Button(action: handleSave) {
                Label("Save as Variant", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(preview == nil)
        }
    }

    private var variantsList: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            SectionHeader("Saved Variants")
            if item.variants.isEmpty {
                InfoRow("No saved variants yet. Send or Save above creates one.")
            } else {
                VStack(spacing: 0) {
                    ForEach(item.variants) { variant in
                        NavigationLink(value: variant) {
                            variantRow(variant)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func variantRow(_ variant: Variant) -> some View {
        HStack(spacing: Theme.Spacing.m) {
            VariantThumbnailView(variant: variant)
                .frame(width: 52, height: 52)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("\(variant.targetWidth)×\(variant.targetHeight)")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                Text(variant.createdDate, style: .date)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, Theme.Spacing.xs)
        .contentShape(Rectangle())
    }

    // MARK: - Actions

    /// Initialize the selection when the view appears (`initial: true`) and
    /// keep it valid as the registry changes, via #0066's last-used
    /// resolver.
    private func initializeSelectionIfNeeded() {
        guard selectedDisplayID == nil || !displays.contains(where: { $0.id == selectedDisplayID }) else { return }
        selectedDisplayID = coordinator.resolveLastUsedDisplay(among: displays)?.id
    }

    private func loadPreview() async {
        guard let display = selectedDisplay else {
            preview = nil
            return
        }
        do {
            preview = try await coordinator.fittedPreview(for: item, display: display)
        } catch {
            preview = nil
            flashError(error.localizedDescription)
        }
    }

    private func handleSendToggle() {
        if isSending {
            AppLog.ftDiscovery.info("User requested stop of continuous send")
            sendController.stop()
            return
        }

        guard let display = selectedDisplay, let preview else { return }

        errorMessage = nil
        successMessage = nil
        infoMessage = nil

        let displayName = display.displayName
        // Offset = the preview's centering offset on this display, plus the
        // display's own stored default offset — see `FTSendPlan`'s doc
        // comment for why the two are additive.
        let plan = FTSendPlan.make(
            preview: preview,
            host: display.host,
            port: display.port,
            layer: display.layer,
            displayOffsetX: display.offsetX,
            displayOffsetY: display.offsetY
        )

        AppLog.ftDiscovery.info("Starting continuous send to \(displayName, privacy: .public) at \(plan.payload.host, privacy: .public):\(plan.payload.port)")

        sendController.start(
            payload: plan.payload,
            // No steppers here (#0067) — the offset/layer are fixed for the
            // whole send, computed once from the preview + display defaults.
            frameOffset: { (layer: plan.offset.z, offsetX: plan.offset.x, offsetY: plan.offset.y) },
            onError: { message in flashError(message) },
            onStopped: { _ in flashInfo("Stopped sending to \(displayName)") }
        )
    }

    private func handleSave() {
        guard let preview else { return }
        do {
            _ = try coordinator.saveVariant(from: preview)
            flashSuccess("Saved to variants")
        } catch {
            flashError(error.localizedDescription)
        }
    }

    // MARK: - Status banners

    private func flashSuccess(_ message: String) {
        errorMessage = nil
        infoMessage = nil
        successMessage = message
        Task {
            try? await Task.sleep(for: .seconds(3))
            if successMessage == message { successMessage = nil }
        }
    }

    private func flashError(_ message: String) {
        successMessage = nil
        infoMessage = nil
        errorMessage = message
        Task {
            try? await Task.sleep(for: .seconds(6))
            if errorMessage == message { errorMessage = nil }
        }
    }

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
    let sampleItem = GalleryItem(
        originalImagePath: "sample.jpg",
        originalName: "Sample Image",
        originalWidth: 800,
        originalHeight: 600
    )

    GallerySendPopoverView(item: sampleItem, coordinator: GalleryCoordinator())
}
