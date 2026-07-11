import SwiftData
import SwiftUI

/// A pushed list of known Flaschen Taschen displays for a single gallery item
/// (#0061/#0064) — the display-first entry point. Tapping a display
/// auto-creates (or reuses) the aspect-fit, centered variant via
/// ``GalleryCoordinator/createFittedVariant(for:display:)`` and pushes onward
/// to ``VariantDetailView`` with the send offset seeded to the centered
/// value and the display preselected, so the user can send immediately with
/// no manual dimension entry.
///
/// A pushed destination (not a sheet) so the onward push to
/// `VariantDetailView` stays in the same navigation stack — `VariantDetailView`
/// is built as pushed content (nav title, toolbar, `.onDisappear` send-stop),
/// so a sheet would need dismiss-then-push gymnastics.
struct DisplaySendPickerView: View {
    let item: GalleryItem
    let coordinator: GalleryCoordinator

    @Environment(\.modelContext) private var modelContext

    /// Live, auto-updating registry, mirroring ``DisplayRegistryView``'s query.
    @Query(sort: \FlaschenTaschenDisplay.discoveredDate, order: .reverse)
    private var displays: [FlaschenTaschenDisplay]

    /// The display currently creating a fitted variant, if any. Disables the
    /// other rows and shows a spinner in the tapped row so a double-tap can't
    /// kick off two creations.
    @State private var creatingDisplayID: UUID?
    /// The just-created (or reused) variant plus the display it was fitted
    /// for, driving the onward push to `VariantDetailView`.
    @State private var pushTarget: FittedVariantPush?
    /// Local error alert. The root `GalleryListView`'s `currentError` alert is
    /// covered by this pushed view, so failures here need their own surface.
    @State private var errorMessage: String?

    @State private var isScanning = false
    @State private var showManualEntry = false
    @State private var scanResultMessage: String?

    /// Bundles a freshly created (or reused) fitted variant with the display
    /// it was fitted for, so both can be threaded through the item-binding
    /// `navigationDestination` below in a single push. `Hashable` is
    /// synthesized automatically — `Variant` (a SwiftData `@Model`) and
    /// `UUID` both already conform.
    private struct FittedVariantPush: Hashable {
        let variant: Variant
        let displayID: UUID
    }

    var body: some View {
        Group {
            if displays.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(displays) { display in
                        Button {
                            send(to: display)
                        } label: {
                            HStack {
                                DisplayRow(display: display)
                                if creatingDisplayID == display.id {
                                    ProgressView()
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(creatingDisplayID != nil)
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("Send to Display")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button(action: scan) {
                        Label("Scan Network", systemImage: "antenna.radiowaves.left.and.right")
                    }
                    .disabled(isScanning)

                    Button(action: { showManualEntry = true }) {
                        Label("Add Manually", systemImage: "plus")
                    }
                } label: {
                    if isScanning {
                        ProgressView()
                    } else {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .navigationDestination(item: $pushTarget) { push in
            VariantDetailView(
                variant: push.variant, coordinator: coordinator,
                centerOnDisplayID: push.displayID
            )
        }
        .sheet(isPresented: $showManualEntry) {
            DisplayEditorView(mode: .add) { validated, layer in
                try coordinator.addManualDisplay(
                    host: validated.host,
                    port: validated.port,
                    displayName: validated.displayName,
                    displayWidth: validated.width,
                    displayHeight: validated.height,
                    layer: layer,
                    offsetX: validated.offsetX,
                    offsetY: validated.offsetY
                )
            }
        }
        .alert("Scan Complete", isPresented: Binding(
            get: { scanResultMessage != nil },
            set: { if !$0 { scanResultMessage = nil } }
        )) {
            Button("OK") { scanResultMessage = nil }
        } message: {
            Text(scanResultMessage ?? "")
        }
        .alert("Couldn't Create Variant", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .onAppear {
            // Belt-and-suspenders: the coordinator arriving from GalleryListView
            // is already configured, but Scan/Add Manually can be used from
            // here directly, mirroring DisplayRegistryView.
            coordinator.configure(modelContext: modelContext)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "display")
                .font(.system(size: 48))
                .foregroundStyle(.gray)
            Text("No Displays")
                .font(.headline)
            Text("Scan your network or add a display manually")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 12) {
                Button(action: scan) {
                    HStack {
                        if isScanning {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                        }
                        Text("Scan")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isScanning)

                Button(action: { showManualEntry = true }) {
                    HStack {
                        Image(systemName: "plus")
                        Text("Add Manually")
                    }
                }
                .buttonStyle(.bordered)
            }
            .padding(.top, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    /// Create (or reuse) the fitted variant for `display` and push onward to
    /// `VariantDetailView` once it's ready. Guarded by `creatingDisplayID` so
    /// a double-tap (or tapping a second row while the first is in flight)
    /// can't kick off two creations.
    private func send(to display: FlaschenTaschenDisplay) {
        guard creatingDisplayID == nil else { return }
        creatingDisplayID = display.id
        let displayID = display.id
        Task {
            do {
                let variant = try await coordinator.createFittedVariant(for: item, display: display)
                pushTarget = FittedVariantPush(variant: variant, displayID: displayID)
            } catch {
                errorMessage = error.localizedDescription
            }
            creatingDisplayID = nil
        }
    }

    private func scan() {
        guard !isScanning else { return }
        isScanning = true
        Task {
            let result = await coordinator.scanForDisplays()
            isScanning = false
            scanResultMessage = "Found \(result.inserted) new and updated \(result.updated) display\(result.updated == 1 ? "" : "s")."
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

    NavigationStack {
        DisplaySendPickerView(item: sampleItem, coordinator: GalleryCoordinator())
    }
}
