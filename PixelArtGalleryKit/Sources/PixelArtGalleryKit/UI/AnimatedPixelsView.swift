import SwiftUI

/// Drives the animated 2×2 pixel block: every 0.5s one cell fades to a new
/// palette color. Ported from PixelArtConverter. Runs only while on screen.
@Observable
final class AnimatedPixelsViewModel {
    var pixelColors: [Color] = Color.pixelColors

    private var animationTask: Task<Void, Never>?

    func start() {
        guard animationTask == nil else { return }
        animationTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { break }
                withAnimation(.easeInOut(duration: 0.75)) {
                    let index = Int.random(in: 0..<pixelColors.count)
                    pixelColors[index] = Color.pixelColors.randomElement() ?? .pixelColor1
                }
            }
        }
    }

    func stop() {
        animationTask?.cancel()
        animationTask = nil
    }
}

/// A lively 2×2 block of large pixels that continuously recolors — used as a
/// playful hero/brand accent (e.g. in the empty gallery state).
struct AnimatedPixelsView: View {
    /// Side length of the whole block.
    var size: CGFloat = 120
    /// Corner radius of the block.
    var cornerRadius: CGFloat = Theme.Radius.card

    @State private var viewModel = AnimatedPixelsViewModel()

    var body: some View {
        let cell = size / 2
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                cellView(0, cell)
                cellView(1, cell)
            }
            HStack(spacing: 0) {
                cellView(2, cell)
                cellView(3, cell)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .onAppear { viewModel.start() }
        .onDisappear { viewModel.stop() }
    }

    private func cellView(_ index: Int, _ cell: CGFloat) -> some View {
        viewModel.pixelColors[index]
            .frame(width: cell, height: cell)
    }
}

#Preview { AnimatedPixelsView() }
