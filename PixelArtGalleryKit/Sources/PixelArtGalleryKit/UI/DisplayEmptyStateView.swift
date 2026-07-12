import SwiftUI

/// Shared "no displays yet" empty state: Scan Network / Add Manually
/// affordances.
///
/// Extracted from ``DisplayRegistryView`` (#0067) so the send popover
/// (`GallerySendPopoverView`) can show the same call-to-action instead of a
/// dead display picker when the registry is empty — a rare path, since
/// `GalleryListView` seeds the built-in default display (#0021), but one
/// that must still work (e.g. the user deleted every display).
struct DisplayEmptyStateView: View {
    let coordinator: GalleryCoordinator

    @State private var isScanning = false
    @State private var showManualEntry = false
    @State private var scanResultMessage: String?

    var body: some View {
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
    DisplayEmptyStateView(coordinator: GalleryCoordinator())
}
