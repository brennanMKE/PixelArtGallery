import SwiftUI

/// The gallery's top banner: the app name over a vibrant, full-strength pixel
/// wallpaper. Replaces the plain `.navigationTitle("Gallery")` with a
/// deliberate hero element (#0070). Static (non-collapsing) for v1 — it does
/// not scroll away or resize; a collapsing/large-title-style effect is a
/// possible follow-on, not in scope here.
struct GalleryBannerView: View {
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            BackgroundPixelsView(style: .vibrant)

            // Bottom scrim so the title reads over the busy pattern.
            LinearGradient(
                colors: [.clear, .black.opacity(0.45)],
                startPoint: .top, endPoint: .bottom
            )

            Text("Pixel Art Gallery")
                .font(.largeTitle.bold())
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
                .padding(Theme.Spacing.l)
        }
        .frame(height: 128) // Fixed content height; simple and predictable.
        .frame(maxWidth: .infinity)
        .clipped()
        .ignoresSafeArea(edges: .top) // Pixels extend under the status bar / transparent nav bar.
        .accessibilityAddTraits(.isHeader)
    }
}

#Preview("Light") { GalleryBannerView().preferredColorScheme(.light) }
#Preview("Dark") { GalleryBannerView().preferredColorScheme(.dark) }
