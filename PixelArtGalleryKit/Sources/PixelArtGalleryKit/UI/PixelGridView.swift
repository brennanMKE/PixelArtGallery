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
            // Canvas grid
            ScrollView([.horizontal, .vertical]) {
                Canvas { context, size in
                    drawPixelGrid(in: &context)
                }
                .frame(width: viewModel.displaySize.width, height: viewModel.displaySize.height)
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
    }
}

#Preview {
    PixelGridView()
}
