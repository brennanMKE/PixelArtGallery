import SwiftUI

/// The bottom action bar for the gallery on iOS: Settings (left), a large
/// centered "add image" `+` (the primary affordance), and Sort (right).
/// Replaces the top-toolbar actions on iOS (#0071) — macOS keeps its native
/// top toolbar. A dumb, state-free view: it owns no state of its own, only a
/// sort binding and two closures, so `GalleryListView` keeps ownership of
/// what happens and the bar stays easy to preview and reason about. Flat —
/// not raised above the bar line — at a flatter, shorter height (#0072; the
/// raised tab-bar-center style from #0071's original ship was the sanctioned
/// fallback once the raise was found to make the bar too tall).
struct GalleryBottomBar: View {
    @Binding var sortOrderRawValue: String
    let onAddImage: () -> Void
    let onShowSettings: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            // Left slot — Settings.
            Button(action: onShowSettings) {
                Label("Settings", systemImage: "gearshape")
                    .labelStyle(.iconOnly)
                    .font(.title3)
            }
            .frame(maxWidth: .infinity, minHeight: 44)

            // Center — the primary add-image affordance. Still unmistakably
            // primary (gold fill, white glyph) at exactly the 44pt minimum
            // tap target, sitting flat in the bar rather than raised.
            Button(action: onAddImage) {
                Image(systemName: "plus")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color.pixelAccent))
                    .shadow(radius: 2, y: 1)
            }
            .accessibilityLabel("Add Image")

            // Right slot — Sort (same Menu/Picker as the former toolbar item).
            Menu {
                Picker("Sort By", selection: $sortOrderRawValue) {
                    ForEach(GallerySortOrder.allCases, id: \.rawValue) { order in
                        Text(order.displayName).tag(order.rawValue)
                    }
                }
            } label: {
                Label("Sort", systemImage: "arrow.up.arrow.down")
                    .labelStyle(.iconOnly)
                    .font(.title3)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .padding(.vertical, Theme.Spacing.xs)
        .padding(.horizontal, Theme.Spacing.l)
        .background(.bar, ignoresSafeAreaEdges: .bottom)
        .overlay(alignment: .top) { Divider() }
    }
}

#Preview {
    @Previewable @State var sortOrderRawValue = GallerySortOrder.newestFirst.rawValue

    VStack {
        Spacer()
        GalleryBottomBar(
            sortOrderRawValue: $sortOrderRawValue,
            onAddImage: {},
            onShowSettings: {}
        )
    }
}
