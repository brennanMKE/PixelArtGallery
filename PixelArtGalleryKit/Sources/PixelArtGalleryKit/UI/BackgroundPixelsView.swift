import SwiftUI

/// State for the full-bleed random-pixel wallpaper: a grid of softly-tinted
/// squares regenerated when the size or color scheme changes. Ported from
/// PixelArtConverter.
@Observable
final class BackgroundPixelsViewModel {
    var pixelGrid: [[Color]] = []
    var size: CGSize = .zero

    let pixelSize: CGFloat = 8.0

    var gridColumns: Int {
        guard size.width > 0 else { return 0 }
        return Int(ceil(size.width / pixelSize))
    }

    var gridRows: Int {
        guard size.height > 0 else { return 0 }
        return Int(ceil(size.height / pixelSize))
    }

    func generatePixelGrid(isDarkMode: Bool = false) {
        let colors = isDarkMode ? Color.darkerPixelColors : Color.lighterPixelColors
        let cols = gridColumns
        let rows = gridRows
        guard cols > 0, rows > 0 else {
            pixelGrid = []
            return
        }
        pixelGrid = (0..<rows).map { _ in
            (0..<cols).map { _ in
                colors.randomElement() ?? .pixelColor1
            }
        }
    }
}

/// A subtle, full-bleed wallpaper of 8pt pixel tiles in the app palette. Sits
/// behind the app content so every screen feels alive without competing with it.
struct BackgroundPixelsView: View {
    @State private var viewModel = BackgroundPixelsViewModel()
    @Environment(\.colorScheme) private var colorScheme

    /// Opacity of the wallpaper — kept low so foreground content stays legible.
    var opacity: Double = 0.5

    var body: some View {
        Canvas { context, _ in
            guard !viewModel.pixelGrid.isEmpty, viewModel.pixelSize > 0 else { return }
            let cols = viewModel.pixelGrid[0].count
            let rows = viewModel.pixelGrid.count
            let cell = viewModel.pixelSize
            for row in 0..<rows {
                for col in 0..<cols {
                    let rect = CGRect(
                        x: CGFloat(col) * cell,
                        y: CGFloat(row) * cell,
                        width: cell,
                        height: cell
                    )
                    context.fill(Path(rect), with: .color(viewModel.pixelGrid[row][col]))
                }
            }
        }
        .opacity(opacity)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onGeometryChange(for: CGSize.self, of: { $0.size }, action: { newSize in
            let old = viewModel.size
            viewModel.size = newSize
            let oldCols = old.width > 0 ? Int(ceil(old.width / viewModel.pixelSize)) : 0
            let oldRows = old.height > 0 ? Int(ceil(old.height / viewModel.pixelSize)) : 0
            let newCols = newSize.width > 0 ? Int(ceil(newSize.width / viewModel.pixelSize)) : 0
            let newRows = newSize.height > 0 ? Int(ceil(newSize.height / viewModel.pixelSize)) : 0
            if oldCols != newCols || oldRows != newRows {
                viewModel.generatePixelGrid(isDarkMode: colorScheme == .dark)
            }
        })
        .task {
            if viewModel.gridColumns > 0, viewModel.gridRows > 0 {
                viewModel.generatePixelGrid(isDarkMode: colorScheme == .dark)
            }
        }
        .onChange(of: colorScheme) { _, newScheme in
            viewModel.generatePixelGrid(isDarkMode: newScheme == .dark)
        }
        .allowsHitTesting(false)
    }
}

#Preview("Light") { BackgroundPixelsView().preferredColorScheme(.light) }
#Preview("Dark") { BackgroundPixelsView().preferredColorScheme(.dark) }
