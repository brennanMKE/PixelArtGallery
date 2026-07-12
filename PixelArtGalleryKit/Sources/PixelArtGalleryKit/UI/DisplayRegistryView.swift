import SwiftData
import SwiftUI

/// Lists all persisted Flaschen Taschen displays and lets the user manage them
/// in place: edit, delete, run an mDNS scan to discover more, or add one
/// manually (#0054). This is now the sole home for display management —
/// embedded directly in ``SettingsView`` on both platforms — rather than a
/// separate destination reachable only from the gallery toolbar.
///
/// The view owns the live `@Query`; the coordinator handles mutations (edit,
/// delete, discovery merge) through its injected `ModelContext`, mirroring the
/// pattern in ``GalleryListView``.
struct DisplayRegistryView: View {
    let coordinator: GalleryCoordinator

    @Environment(\.modelContext) private var modelContext

    /// Live, auto-updating registry sourced directly from SwiftData.
    @Query(sort: \FlaschenTaschenDisplay.discoveredDate, order: .reverse)
    private var displays: [FlaschenTaschenDisplay]

    @State private var isScanning = false
    @State private var showManualEntry = false
    @State private var editTarget: FlaschenTaschenDisplay?
    @State private var scanResultMessage: String?

    /// Whether the built-in seeded default display (`source == defaultSource`)
    /// still exists. When it doesn't — because the user deleted it while
    /// keeping other displays — a "Restore Default Display" affordance is
    /// shown so it isn't gone for good.
    private var hasDefaultDisplay: Bool {
        displays.contains { $0.source == FlaschenTaschenDisplay.defaultSource }
    }

    var body: some View {
        Group {
            if displays.isEmpty {
                emptyState
            } else {
                List {
                    if !hasDefaultDisplay {
                        restoreDefaultSection
                    }
                    #if os(macOS)
                    addDisplaySection
                    #endif
                    ForEach(displays) { display in
                        Button {
                            editTarget = display
                        } label: {
                            DisplayRow(display: display)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button {
                                editTarget = display
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                coordinator.deleteDisplay(display)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            coordinator.deleteDisplay(displays[index])
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("Settings")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        #endif
        // iOS keeps the nav-bar "+" pull-down menu. macOS deliberately has no
        // toolbar item here: the Settings scene renders every toolbar control
        // inside a prominent Liquid-Glass capsule (the stray "extra circle"
        // around the "+", #0083), so on macOS the Scan/Add actions live in the
        // list body (`addDisplaySection`) and the empty state instead.
        #if os(iOS)
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
        #endif
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
        .sheet(item: $editTarget) { target in
            DisplayEditorView(mode: .edit(target)) { validated, layer in
                try coordinator.updateDisplay(target, with: validated, layer: layer)
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
        .onAppear {
            coordinator.configure(modelContext: modelContext)
        }
    }

    #if os(macOS)
    /// macOS-only: Scan/Add actions as labeled rows at the top of the list.
    /// They live in the body rather than the Settings-window toolbar because the
    /// macOS Settings scene wraps every toolbar control in a prominent
    /// Liquid-Glass capsule — the stray "extra circle" around the "+" (#0083).
    /// Body rows avoid that and read as clear, discoverable actions. iOS keeps
    /// the nav-bar "+" menu.
    private var addDisplaySection: some View {
        Section {
            Button(action: scan) {
                if isScanning {
                    Label {
                        Text("Scanning…")
                    } icon: {
                        ProgressView().controlSize(.small)
                    }
                } else {
                    Label("Scan Network", systemImage: "antenna.radiowaves.left.and.right")
                }
            }
            .disabled(isScanning)

            Button(action: { showManualEntry = true }) {
                Label("Add Manually", systemImage: "plus")
            }
        }
    }
    #endif

    /// Shown above the list when the seeded default display has been deleted
    /// while other displays remain, so it's never gone for good.
    private var restoreDefaultSection: some View {
        Section {
            HStack(alignment: .top) {
                Image(systemName: "display")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text("No default display is configured.")
                    Button("Restore Default Display") {
                        coordinator.restoreDefaultDisplay()
                    }
                }
            }
        }
    }

    /// Extracted to ``DisplayEmptyStateView`` (#0067) so the send popover
    /// shows the identical Scan/Add affordances when the registry is empty.
    private var emptyState: some View {
        DisplayEmptyStateView(coordinator: coordinator)
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
    NavigationStack {
        DisplayRegistryView(coordinator: GalleryCoordinator())
    }
}
