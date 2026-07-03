import SwiftUI

/// Canvas-based pixel grid renderer that fits the whole grid by default and
/// supports zoom (pinch + buttons), pan-when-zoomed, tap-to-select, and reset.
struct PixelGridView: View {
    @State private var viewModel: PixelGridViewModel

    // Gesture bookkeeping so pinch/drag accumulate from where they started.
    @State private var zoomAtGestureStart: Double = 1.0
    @State private var isZooming = false
    @State private var panAtGestureStart: CGSize = .zero
    @State private var isPanning = false

    /// Initialize with optional variant data.
    init(variant: Variant? = nil) {
        if let variant = variant {
            do {
                let model = try PixelGridViewModel(variant: variant)
                AppLog.gridRenderer.debug("Rendering \(model.gridWidth)×\(model.gridHeight) grid for variant \(variant.id)")
                _viewModel = State(initialValue: model)
            } catch {
                AppLog.gridRenderer.error("Failed to load variant \(variant.id) into grid; using empty grid: \(error.localizedDescription, privacy: .public)")
                _viewModel = State(initialValue: PixelGridViewModel())
            }
        } else {
            _viewModel = State(initialValue: PixelGridViewModel())
        }
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.s) {
            selectionReadout

            GeometryReader { geo in
                let container = geo.size
                Canvas { context, _ in
                    drawPixelGrid(in: &context, container: container)
                }
                .frame(width: container.width, height: container.height)
                .contentShape(Rectangle())
                .gesture(magnifyGesture(container: container))
                .simultaneousGesture(panGesture(container: container))
                .simultaneousGesture(tapGesture(container: container))
                .clipped()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.opacity(0.05))

            zoomControls
        }
    }

    // MARK: - Gestures

    private func magnifyGesture(container: CGSize) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                if !isZooming {
                    isZooming = true
                    zoomAtGestureStart = viewModel.zoomLevel
                }
                viewModel.setZoom(zoomAtGestureStart * value.magnification)
            }
            .onEnded { _ in
                isZooming = false
                zoomAtGestureStart = viewModel.zoomLevel
            }
    }

    private func panGesture(container: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                guard !viewModel.isFitToView else { return }
                if !isPanning {
                    isPanning = true
                    panAtGestureStart = viewModel.clampedPan(in: container)
                }
                viewModel.panOffset = CGSize(
                    width: panAtGestureStart.width + value.translation.width,
                    height: panAtGestureStart.height + value.translation.height
                )
            }
            .onEnded { _ in
                isPanning = false
                viewModel.panOffset = viewModel.clampedPan(in: container)
            }
    }

    private func tapGesture(container: CGSize) -> some Gesture {
        SpatialTapGesture()
            .onEnded { value in
                viewModel.selectPixel(at: value.location, in: container)
            }
    }

    // MARK: - Selection readout

    /// Readout showing the coordinate and RGBA value of the selected pixel.
    @ViewBuilder
    private var selectionReadout: some View {
        HStack(spacing: Theme.Spacing.m) {
            if let selected = viewModel.selectedPixel {
                let color = viewModel.pixelColor(x: selected.x, y: selected.y)
                RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                    .fill(swiftUIColor(color))
                    .frame(width: 20, height: 20)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                            .stroke(.secondary, lineWidth: 0.5)
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
        .padding(.vertical, Theme.Spacing.xs)
        .frame(maxWidth: .infinity)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
    }

    // MARK: - Zoom controls

    private var zoomControls: some View {
        HStack(spacing: Theme.Spacing.m) {
            Button {
                viewModel.zoomOut()
            } label: {
                Image(systemName: "minus.magnifyingglass")
            }
            .disabled(viewModel.isFitToView)

            Text(String(format: "%.0f%%", viewModel.zoomLevel * 100))
                .monospacedDigit()
                .frame(minWidth: 60)

            Button {
                viewModel.zoomIn()
            } label: {
                Image(systemName: "plus.magnifyingglass")
            }
            .disabled(viewModel.zoomLevel >= viewModel.maxZoom)

            Spacer()

            Button("Size to Fit") {
                viewModel.reset()
            }
            .disabled(viewModel.isFitToView && viewModel.panOffset == .zero)
        }
        .padding()
        .background(.quaternary, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
    }

    // MARK: - Drawing

    private func swiftUIColor(_ c: PixelColor) -> Color {
        Color(
            red: Double(c.red) / 255.0,
            green: Double(c.green) / 255.0,
            blue: Double(c.blue) / 255.0,
            opacity: Double(c.alpha) / 255.0
        )
    }

    private func drawPixelGrid(in context: inout GraphicsContext, container: CGSize) {
        let cell = viewModel.cellSize(in: container)
        guard cell > 0 else { return }
        let origin = viewModel.origin(in: container)

        for y in 0..<viewModel.gridHeight {
            let cellY = origin.y + CGFloat(y) * cell
            if cellY + cell < 0 || cellY > container.height { continue } // cull off-screen rows
            for x in 0..<viewModel.gridWidth {
                let cellX = origin.x + CGFloat(x) * cell
                if cellX + cell < 0 || cellX > container.width { continue } // cull off-screen columns
                let rect = CGRect(x: cellX, y: cellY, width: cell, height: cell)
                context.fill(Path(rect), with: .color(swiftUIColor(viewModel.pixelColor(x: x, y: y))))
            }
        }

        // Grid lines only when cells are large enough to read as a grid.
        if cell >= 6 {
            let content = viewModel.contentSize(in: container)
            var lines = Path()
            for x in 0...viewModel.gridWidth {
                let xp = origin.x + CGFloat(x) * cell
                lines.move(to: CGPoint(x: xp, y: origin.y))
                lines.addLine(to: CGPoint(x: xp, y: origin.y + content.height))
            }
            for y in 0...viewModel.gridHeight {
                let yp = origin.y + CGFloat(y) * cell
                lines.move(to: CGPoint(x: origin.x, y: yp))
                lines.addLine(to: CGPoint(x: origin.x + content.width, y: yp))
            }
            context.stroke(lines, with: .color(.gray.opacity(0.3)), lineWidth: 0.5)
        }

        // Selected-cell highlight.
        if let selected = viewModel.selectedPixel {
            let rect = CGRect(
                x: origin.x + CGFloat(selected.x) * cell,
                y: origin.y + CGFloat(selected.y) * cell,
                width: cell,
                height: cell
            )
            context.stroke(Path(rect), with: .color(.yellow), lineWidth: max(2, cell * 0.15))
            context.stroke(Path(rect), with: .color(.black), lineWidth: 1)
        }
    }
}

#Preview {
    PixelGridView()
}
