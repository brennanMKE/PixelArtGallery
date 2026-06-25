import SwiftUI

/// Canvas-based pixel grid renderer with zoom controls
struct PixelGridView: View {
    @State private var viewModel: PixelGridViewModel

    /// Initialize with optional variant data
    init(variant: Variant? = nil) {
        if let variant = variant {
            do {
                _viewModel = State(initialValue: try PixelGridViewModel(variant: variant))
            } catch {
                // Fallback to empty grid on error
                _viewModel = State(initialValue: PixelGridViewModel())
            }
        } else {
            _viewModel = State(initialValue: PixelGridViewModel())
        }
    }

    var body: some View {
        VStack {
            // Selected-pixel readout
            selectionReadout

            // Canvas grid
            ScrollView([.horizontal, .vertical]) {
                Canvas { context, size in
                    drawPixelGrid(in: &context)
                }
                .frame(width: viewModel.displaySize.width, height: viewModel.displaySize.height)
                #if os(iOS)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onEnded { value in
                            viewModel.selectPixel(at: value.location)
                        }
                )
                #elseif os(macOS)
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        viewModel.selectPixel(at: location)
                    case .ended:
                        viewModel.clearSelection()
                    }
                }
                #endif
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.opacity(0.05))

            // Zoom controls
            HStack(spacing: 12) {
                Button(action: viewModel.zoomOut) {
                    Image(systemName: "minus.magnifyingglass")
                }

                Text(String(format: "%.0f%%", viewModel.zoomLevel * 100))
                    .frame(minWidth: 60)

                Button(action: viewModel.zoomIn) {
                    Image(systemName: "plus.magnifyingglass")
                }

                Spacer()

                Button(action: viewModel.resetZoom) {
                    Text("Reset")
                }
            }
            .padding()
            .background(Color.gray.opacity(0.1))
        }
        .navigationTitle("Pixel Grid")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    /// Readout showing the coordinate and RGBA value of the selected pixel.
    @ViewBuilder
    private var selectionReadout: some View {
        HStack(spacing: 12) {
            if let selected = viewModel.selectedPixel {
                let color = viewModel.pixelColor(x: selected.x, y: selected.y)
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(
                        red: Double(color.red) / 255.0,
                        green: Double(color.green) / 255.0,
                        blue: Double(color.blue) / 255.0,
                        opacity: Double(color.alpha) / 255.0
                    ))
                    .frame(width: 20, height: 20)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(Color.gray.opacity(0.5), lineWidth: 0.5)
                    )
                Text("(\(selected.x), \(selected.y))")
                    .font(.system(.body, design: .monospaced))
                Text("RGBA \(color.red), \(color.green), \(color.blue), \(color.alpha)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            } else {
                Text("No pixel selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(Color.gray.opacity(0.08))
    }

    private func drawPixelGrid(in context: inout GraphicsContext) {
        let pixelSize = viewModel.pixelSize * viewModel.zoomLevel

        for y in 0..<viewModel.gridHeight {
            for x in 0..<viewModel.gridWidth {
                let rect = CGRect(
                    x: CGFloat(x) * pixelSize,
                    y: CGFloat(y) * pixelSize,
                    width: pixelSize,
                    height: pixelSize
                )

                // Get actual pixel color from data
                let pixelColor = viewModel.pixelColor(x: x, y: y)
                let swiftUIColor = Color(
                    red: Double(pixelColor.red) / 255.0,
                    green: Double(pixelColor.green) / 255.0,
                    blue: Double(pixelColor.blue) / 255.0,
                    opacity: Double(pixelColor.alpha) / 255.0
                )

                var path = Path(roundedRect: rect, cornerRadius: 0)
                context.fill(path, with: .color(swiftUIColor))

                // Draw border
                path = Path(roundedRect: rect, cornerRadius: 0)
                context.stroke(path, with: .color(.gray.opacity(0.3)), lineWidth: 0.5)
            }
        }

        // Highlight the selected cell on top of the grid
        if let selected = viewModel.selectedPixel {
            let rect = CGRect(
                x: CGFloat(selected.x) * pixelSize,
                y: CGFloat(selected.y) * pixelSize,
                width: pixelSize,
                height: pixelSize
            )
            let highlight = Path(roundedRect: rect, cornerRadius: 0)
            context.stroke(highlight, with: .color(.yellow), lineWidth: max(2, pixelSize * 0.1))
            context.stroke(highlight, with: .color(.black), lineWidth: 1)
        }
    }
}

#Preview {
    PixelGridView()
}
