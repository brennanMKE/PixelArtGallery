import SwiftUI

/// The bottom action bar for the gallery on iOS: Settings (left), a large
/// centered "add image" `+` (the primary affordance), and Sort (right).
/// Replaces the top-toolbar actions on iOS (#0071) — macOS keeps its native
/// top toolbar. A dumb, state-free view: it owns no state of its own, only a
/// sort binding and two closures, so `GalleryListView` keeps ownership of
/// what happens and the bar stays easy to preview and reason about.
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
            .frame(maxWidth: .infinity)

            // Center — the primary add-image affordance, raised slightly
            // above the bar line (tab-bar-center-action style).
            Button(action: onAddImage) {
                Image(systemName: "plus")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 60, height: 60)
                    .background(Circle().fill(Color.pixelAccent))
                    .shadow(radius: 3, y: 2)
            }
            .accessibilityLabel("Add Image")
            .offset(y: -10)

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
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, Theme.Spacing.s)
        .padding(.top, 10) // Matches the `+` button's raise so it clears the divider.
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
