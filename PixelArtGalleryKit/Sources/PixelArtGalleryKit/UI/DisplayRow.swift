import SwiftUI

/// A single row summarizing a Flaschen Taschen display: name, endpoint, and
/// resolution. Extracted from ``DisplayRegistryView`` (#0064) so it can be
/// reused by other display-list surfaces without duplicating the layout.
struct DisplayRow: View {
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
