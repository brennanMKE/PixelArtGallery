import SwiftUI

/// Lightweight design tokens so screens stop hand-rolling corner radii, spacing,
/// and gray fills. Direction: "Native + light personality" — system components
/// plus one accent (the asset `AccentColor`, applied via `.tint`) and a
/// consistent card treatment.
nonisolated enum Theme {
    enum Spacing {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
    }

    enum Radius {
        static let small: CGFloat = 6
        static let control: CGFloat = 8
        static let card: CGFloat = 12
    }
}

/// The app's standard card: padding + a subtle fill + rounded corners.
private struct CardModifier: ViewModifier {
    var padding: CGFloat = Theme.Spacing.l

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                // Frosted material so the colorful pixel background shows through.
                .regularMaterial,
                in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
            )
    }
}

extension View {
    /// Wrap content in the app's standard card treatment.
    func card(padding: CGFloat = Theme.Spacing.l) -> some View {
        modifier(CardModifier(padding: padding))
    }
}
