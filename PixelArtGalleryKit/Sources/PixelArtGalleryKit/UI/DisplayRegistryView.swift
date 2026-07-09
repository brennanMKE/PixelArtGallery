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
        .sheet(isPresented: $showManualEntry) {
            DisplayEditorView(mode: .add) { validated, layer in
                try coordinator.addManualDisplay(
                    host: validated.host,
                    port: validated.port,
                    displayName: validated.displayName,
                    displayWidth: validated.width,
                    displayHeight: validated.height,
                    layer: layer
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

/// A single row in the display registry showing name, endpoint, and resolution.
private struct DisplayRow: View {
    let display: FlaschenTaschenDisplay

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "display")
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(display.displayName)
                    .font(.headline)
                Text(display.endpoint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Text(display.resolution)
                    Text("·")
                    Text(sourceLabel)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Human-readable origin of the display record.
    private var sourceLabel: String {
        switch display.source {
        case "mdns":
            return "Discovered"
        case FlaschenTaschenDisplay.defaultSource:
            return "Default"
        default:
            return "Manual"
        }
    }
}

#Preview {
    NavigationStack {
        DisplayRegistryView(coordinator: GalleryCoordinator())
    }
}
