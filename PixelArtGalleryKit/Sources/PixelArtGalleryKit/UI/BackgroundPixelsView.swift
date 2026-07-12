import SwiftUI

/// The visual treatment of a ``BackgroundPixelsView`` instance — how its
/// palette is chosen per color scheme and what opacity it defaults to.
/// A pure, `nonisolated` selector so it stays cheaply testable off the main
/// actor even though the package default-isolates to `@MainActor` (#0070).
nonisolated enum PixelWallpaperStyle {
    /// Current wallpaper behavior: softly-tinted lighter/darker palette at
    /// opacity 0.5 — calm enough to sit full-bleed behind content.
    case subtle
    /// Full-strength, saturated palette at opacity 1.0 in BOTH color
    /// schemes — used for the banner hero, where the pixels are the point.
    case vibrant

    /// The palette to draw from for the given color scheme.
    func palette(isDark: Bool) -> [Color] {
        switch self {
        case .subtle: isDark ? Color.darkerPixelColors : Color.lighterPixelColors
        case .vibrant: Color.pixelColors
        }
    }

    /// The opacity this style renders at when the caller doesn't override it.
    var defaultOpacity: Double {
        switch self {
        case .subtle: 0.5
        case .vibrant: 1.0
        }
    }
}

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

    /// Regenerates the grid from the given palette. Grid generation itself is
    /// palette-agnostic — palette selection lives in ``PixelWallpaperStyle``.
    func generatePixelGrid(palette: [Color]) {
        let cols = gridColumns
        let rows = gridRows
        guard cols > 0, rows > 0 else {
            pixelGrid = []
            return
        }
        pixelGrid = (0..<rows).map { _ in
            (0..<cols).map { _ in
                palette.randomElement() ?? .pixelColor1
            }
        }
    }
}

/// A full-bleed wallpaper of 8pt pixel tiles in the app palette. By default a
/// subtle backdrop that sits behind app content so every screen feels alive
/// without competing with it; pass `style: .vibrant` for a saturated hero use
/// (e.g. the gallery banner, #0070).
struct BackgroundPixelsView: View {
    @State private var viewModel = BackgroundPixelsViewModel()
    @Environment(\.colorScheme) private var colorScheme

    /// The visual treatment — defaults to the original subtle wallpaper.
    var style: PixelWallpaperStyle = .subtle

    /// Opacity of the wallpaper — defaults to the style's own default so
    /// `.subtle` stays at 0.5 and `.vibrant` renders fully opaque; pass an
    /// explicit value to override either.
    var opacity: Double?

    private var resolvedOpacity: Double { opacity ?? style.defaultOpacity }

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
        .opacity(resolvedOpacity)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onGeometryChange(for: CGSize.self, of: { $0.size }, action: { newSize in
            let old = viewModel.size
            viewModel.size = newSize
            let oldCols = old.width > 0 ? Int(ceil(old.width / viewModel.pixelSize)) : 0
            let oldRows = old.height > 0 ? Int(ceil(old.height / viewModel.pixelSize)) : 0
            let newCols = newSize.width > 0 ? Int(ceil(newSize.width / viewModel.pixelSize)) : 0
            let newRows = newSize.height > 0 ? Int(ceil(newSize.height / viewModel.pixelSize)) : 0
            if oldCols != newCols || oldRows != newRows {
                viewModel.generatePixelGrid(palette: style.palette(isDark: colorScheme == .dark))
            }
        })
        .task {
            if viewModel.gridColumns > 0, viewModel.gridRows > 0 {
                viewModel.generatePixelGrid(palette: style.palette(isDark: colorScheme == .dark))
            }
        }
        .onChange(of: colorScheme) { _, newScheme in
            viewModel.generatePixelGrid(palette: style.palette(isDark: newScheme == .dark))
        }
        .allowsHitTesting(false)
    }
}

#Preview("Light") { BackgroundPixelsView().preferredColorScheme(.light) }
#Preview("Dark") { BackgroundPixelsView().preferredColorScheme(.dark) }
#Preview("Vibrant") { BackgroundPixelsView(style: .vibrant) }
