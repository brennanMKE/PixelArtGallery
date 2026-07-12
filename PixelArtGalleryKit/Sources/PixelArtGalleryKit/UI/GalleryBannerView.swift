import SwiftUI

/// The gallery's collapsing header: the app name over a vibrant, full-strength
/// pixel wallpaper (#0070). Standard iOS large-title-style behavior (#0072):
/// starts expanded at ``GalleryHeaderMetrics/expandedHeight`` with a large
/// title, then shrinks and pins to ``GalleryHeaderMetrics/compactHeight`` as
/// `scrollOffset` grows, driven by the enclosing `ScrollView`'s
/// `onScrollGeometryChange`. Pass the default `scrollOffset` of `0` for a
/// static, fully-expanded header (previews, the empty state, macOS).
struct GalleryBannerView: View {
    /// How far the content backing this header has scrolled — `0` at rest
    /// (or rubber-banding past the top), growing toward
    /// ``GalleryHeaderMetrics/collapseRange`` as the header collapses.
    var scrollOffset: CGFloat = 0

    private var height: CGFloat { GalleryHeaderMetrics.height(forScrollOffset: scrollOffset) }
    private var titleSize: CGFloat { GalleryHeaderMetrics.titleSize(forScrollOffset: scrollOffset) }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Bottom scrim so the title reads over the busy pattern. Lives in
            // the content band (not the bleeding background) so it scales
            // with the header's current height as it collapses.
            LinearGradient(
                colors: [.clear, .black.opacity(0.45)],
                startPoint: .top, endPoint: .bottom
            )

            Text("Pixel Art Gallery")
                .font(.system(size: titleSize, weight: .bold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
                .padding(Theme.Spacing.l)
        }
        // The header's layout frame stays inside the safe area — no
        // ignoresSafeArea on this framed view. Splitting layout (this frame)
        // from render (the ignoresSafeArea below, scoped to the background
        // only) was the root cause of the black bar under the banner (#0072):
        // previously ignoresSafeArea applied to the whole fixed-height view,
        // so its painted pixels stopped short of the taller layout slot a
        // parent VStack reserved, leaving a bare strip of the matte
        // background exposed.
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipped()
        .background(alignment: .top) {
            // Only the pixel backdrop bleeds under the status bar, and only
            // on iOS. A fixed-size canvas (independent of `height`) so
            // `BackgroundPixelsViewModel` never sees its size change during
            // the collapse animation — its regen fires on column/row-count
            // change, and a per-frame height change would visibly
            // re-randomize the grid. `.clipped()` is applied to the canvas
            // itself (cropping it to the header's current bounds) *before*
            // `.ignoresSafeArea` expands the already-cropped container's
            // render bounds up past the status bar — the container bleeds,
            // layout is unaffected. On macOS the top safe area is the window
            // title bar/toolbar, not a status bar, so `.ignoresSafeArea` is
            // gated to iOS only (#0080): the banner stays clipped to its
            // 128pt band and sits below the title bar instead of bleeding
            // pixels behind the traffic lights and toolbar controls.
            Color.clear
                .overlay(alignment: .top) {
                    BackgroundPixelsView(style: .vibrant)
                        .frame(height: 220) // expanded height (128) + generous status-bar allowance; constant.
                }
                .clipped()
                #if os(iOS)
                .ignoresSafeArea(edges: .top)
                #endif
        }
        .accessibilityAddTraits(.isHeader)
    }
}

#Preview("Light — expanded") { GalleryBannerView().preferredColorScheme(.light) }
#Preview("Dark — expanded") { GalleryBannerView().preferredColorScheme(.dark) }
#Preview("Collapsed") { GalleryBannerView(scrollOffset: GalleryHeaderMetrics.collapseRange) }
