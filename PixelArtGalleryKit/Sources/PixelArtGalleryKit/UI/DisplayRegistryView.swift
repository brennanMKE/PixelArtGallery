import SwiftData
import SwiftUI

/// Lists all persisted Flaschen Taschen displays and lets the user manage them:
/// rename, delete, run an mDNS scan to discover more, or add one manually.
///
/// The view owns the live `@Query`; the coordinator handles mutations (rename,
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
    @State private var renameTarget: FlaschenTaschenDisplay?
    @State private var renameText = ""
    @State private var scanResultMessage: String?

    var body: some View {
        Group {
            if displays.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(displays) { display in
                        DisplayRow(display: display)
                            .contextMenu {
                                Button {
                                    beginRename(display)
                                } label: {
                                    Label("Rename", systemImage: "pencil")
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
            }
        }
        .navigationTitle("Displays")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
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
            ManualDisplayEntryView { validated in
                try coordinator.addManualDisplay(
                    host: validated.host,
                    port: validated.port,
                    displayName: validated.displayName,
                    displayWidth: validated.width,
                    displayHeight: validated.height
                )
            }
        }
        .alert("Rename Display", isPresented: Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) { renameTarget = nil }
            Button("Save") {
                if let target = renameTarget {
                    coordinator.renameDisplay(target, to: renameText)
                }
                renameTarget = nil
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

    private func beginRename(_ display: FlaschenTaschenDisplay) {
        renameText = display.displayName
        renameTarget = display
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
                    Text(display.source == "mdns" ? "Discovered" : "Manual")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#Preview {
    NavigationStack {
        DisplayRegistryView(coordinator: GalleryCoordinator())
    }
}
