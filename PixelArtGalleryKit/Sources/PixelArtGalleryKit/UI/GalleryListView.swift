import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// A freshly picked image awaiting a name before it's imported. Carries the raw
/// bytes plus the picker's suggested name (if any) so the naming sheet can
/// prefill the field.
private struct PendingImport: Identifiable {
    let id = UUID()
    let imageData: Data
    let suggestedName: String?
}

/// Displays a list of all gallery items with preview thumbnails
public struct GalleryListView: View {
    @State private var coordinator = GalleryCoordinator()
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.modelContext) private var modelContext

    /// A picked image awaiting naming, which drives the import naming sheet.
    @State private var pendingImport: PendingImport?
    /// The gallery item currently being renamed via the rename alert, if any.
    @State private var itemToRename: GalleryItem?
    /// Working text for the rename alert's text field.
    @State private var renameText: String = ""
    /// The gallery item pending delete confirmation, if any.
    @State private var itemToDelete: GalleryItem?
    /// The gallery item whose send popover is presented, if any (#0067).
    @State private var selectedItem: GalleryItem?

    #if os(iOS)
    /// Whether the in-app Settings sheet is presented, triggered from the
    /// gear button in the bottom bar (#0071; iOS only — macOS uses the
    /// standard `Settings` scene instead).
    @State private var showSettings = false
    #endif

    /// Live, auto-updating gallery items sourced directly from SwiftData.
    /// The view owns the query; the coordinator only handles mutations. The
    /// query keeps a stable newest-first base sort; the user-facing ordering
    /// (pinned first, then the chosen sort) is applied in-memory via
    /// ``GallerySortOrder/sortedForGallery(_:)`` (#0035).
    @Query(sort: \GalleryItem.importedDate, order: .reverse) private var galleryItems: [GalleryItem]

    /// The user's chosen sort for unpinned items, persisted across launches.
    /// Stored as the raw value so `@AppStorage` can hold it directly.
    @AppStorage("gallerySortOrder") private var sortOrderRawValue: String = GallerySortOrder.newestFirst.rawValue

    /// The current sort order, falling back to newest-first if the stored raw
    /// value is stale or unknown.
    private var sortOrder: GallerySortOrder {
        GallerySortOrder(rawValue: sortOrderRawValue) ?? .newestFirst
    }

    /// Gallery items in display order: pinned items lead, then the rest in the
    /// user's chosen sort.
    private var sortedItems: [GalleryItem] {
        sortOrder.sortedForGallery(galleryItems)
    }

    public init() {}

    public var body: some View {
        NavigationStack {
            ZStack {
                // Plain matte behind the banner, grid, and empty state — the
                // pixel wallpaper is now confined to the banner above (#0070).
                Color.matteBackground
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    GalleryBannerView()

                    Group {
                        if galleryItems.isEmpty {
                            EmptyStateView(
                                icon: "photo.on.rectangle.angled",
                                title: "No Gallery Items",
                                message: "Import an image to start creating pixel art.",
                                actionLabel: "Import Image",
                                action: { coordinator.showImagePicker = true },
                                animatedHero: true
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            // Adaptive thumbnail grid: column count reflows with
                            // the scene width (more columns on a wide Mac window
                            // or iPad, fewer on iPhone). Sits on the plain matte
                            // background above, not the pixel wallpaper.
                            ScrollView {
                                LazyVGrid(
                                    columns: [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: Theme.Spacing.m)],
                                    alignment: .leading,
                                    spacing: Theme.Spacing.m
                                ) {
                                    ForEach(sortedItems) { item in
                                        galleryCellButton(for: item)
                                    }
                                }
                                .padding(Theme.Spacing.l)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            #if os(iOS)
            // The bottom bar carries Settings, the large centered `+`, and
            // Sort on iOS (#0071) — a safe-area inset so the grid's last row
            // and the empty state both clear the bar rather than sitting
            // behind it.
            .safeAreaInset(edge: .bottom) {
                GalleryBottomBar(
                    sortOrderRawValue: $sortOrderRawValue,
                    onAddImage: { coordinator.showImagePicker = true },
                    onShowSettings: { showSettings = true }
                )
            }
            #endif
            // GalleryItem is no longer a push destination — tapping a cell
            // presents GallerySendPopoverView instead (#0067). GalleryDetailView
            // was retired entirely in #0068.
            .navigationTitle("") // The banner owns the title; no duplicate.
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline) // No large-title gap above the banner.
            .toolbarBackground(.hidden, for: .navigationBar)
            #endif
            #if os(macOS)
            // iOS moves these actions into the bottom bar (#0071) — Settings
            // (gear), Sort, and the large centered `+` — so this toolbar is
            // macOS-only. macOS keeps its native top toolbar with exactly `+`
            // and Sort; it never had a Settings button here since it reaches
            // SettingsView through the app's Settings scene (⌘,).
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { coordinator.showImagePicker = true }) {
                        Image(systemName: "plus")
                    }
                }
                // Sort menu for the unpinned items; the current choice shows a
                // checkmark and persists across launches via AppStorage.
                ToolbarItem(placement: .secondaryAction) {
                    Menu {
                        Picker("Sort By", selection: $sortOrderRawValue) {
                            ForEach(GallerySortOrder.allCases, id: \.rawValue) { order in
                                Text(order.displayName).tag(order.rawValue)
                            }
                        }
                    } label: {
                        Label("Sort", systemImage: "arrow.up.arrow.down")
                    }
                }
            }
            #endif

            // Error alert
            .alert("Error", isPresented: Binding(
                get: { coordinator.currentError != nil },
                set: { if !$0 { coordinator.currentError = nil } }
            )) {
                Button("OK", role: .cancel) { coordinator.currentError = nil }
            } message: {
                Text(coordinator.currentError ?? "")
            }

            // Informational alert (e.g. a duplicate import was skipped). Not an
            // error — surfaces the coordinator's non-error import message.
            .alert("Import", isPresented: Binding(
                get: { coordinator.importMessage != nil },
                set: { if !$0 { coordinator.importMessage = nil } }
            )) {
                Button("OK", role: .cancel) { coordinator.importMessage = nil }
            } message: {
                Text(coordinator.importMessage ?? "")
            }
            .onAppear {
                coordinator.configure(modelContext: modelContext)
                // Seed the built-in default FT display when the registry is
                // completely empty, so Send to Display always has a target
                // (#0021). Idempotent — no-op once any display exists.
                coordinator.seedDefaultDisplayIfNeeded()
            }
            // Rename an existing gallery item.
            .alert("Rename Image", isPresented: Binding(
                get: { itemToRename != nil },
                set: { if !$0 { itemToRename = nil } }
            )) {
                TextField("Imported Image", text: $renameText)
                Button("Cancel", role: .cancel) {
                    itemToRename = nil
                }
                Button("Rename") {
                    if let item = itemToRename {
                        coordinator.renameGalleryItem(item, to: renameText)
                    }
                    itemToRename = nil
                }
            } message: {
                Text("Enter a new name for this image.")
            }
            // Confirm before deleting a gallery item from the row's context
            // menu — deletion also removes its variants and stored files.
            .confirmationDialog(
                "Delete this image?",
                isPresented: Binding(
                    get: { itemToDelete != nil },
                    set: { if !$0 { itemToDelete = nil } }
                ),
                titleVisibility: .visible,
                presenting: itemToDelete
            ) { item in
                Button("Delete Image", role: .destructive) {
                    coordinator.deleteGalleryItem(item)
                    itemToDelete = nil
                }
                Button("Cancel", role: .cancel) {
                    itemToDelete = nil
                }
            } message: { item in
                Text("\(item.originalName) and its variants will be deleted — this can't be undone.")
            }
        }

        // Image picker. Picking surfaces the bytes plus a suggested name,
        // which we hold as a pending import so the user can confirm/edit the name
        // before it's saved.
        #if os(iOS)
        // iOS: PHPicker presented in a sheet.
        .sheet(isPresented: $coordinator.showImagePicker) {
            ImagePickerView { imageData, suggestedName in
                pendingImport = PendingImport(imageData: imageData, suggestedName: suggestedName)
            }
        }
        #elseif os(macOS)
        // macOS: the native file chooser, presented directly — no intermediate
        // sheet and no main-thread-blocking `NSOpenPanel.runModal()`.
        .fileImporter(
            isPresented: $coordinator.showImagePicker,
            allowedContentTypes: [.image]
        ) { result in
            switch result {
            case .success(let url):
                // The app is sandboxed (user-selected-file read-only), so the
                // URL must be accessed within a security scope.
                let didStartAccess = url.startAccessingSecurityScopedResource()
                defer {
                    if didStartAccess { url.stopAccessingSecurityScopedResource() }
                }
                do {
                    let imageData = try Data(contentsOf: url)
                    pendingImport = PendingImport(
                        imageData: imageData,
                        suggestedName: url.deletingPathExtension().lastPathComponent
                    )
                } catch {
                    coordinator.currentError = "Could not read the selected image: \(error.localizedDescription)"
                }
            case .failure(let error):
                coordinator.currentError = error.localizedDescription
            }
        }
        #endif

        // Import naming sheet — prefilled with the suggested name.
        .sheet(item: $pendingImport) { pending in
            ImportNamingView(suggestedName: pending.suggestedName) { name in
                try? await coordinator.createGalleryItem(name: name, imageData: pending.imageData)
            }
        }

        #if os(iOS)
        // In-app Settings — display management (#0054), triggered from the
        // bottom bar's gear button (#0071). SettingsView owns its own
        // NavigationStack and Done button; macOS gets the standard Settings
        // scene instead.
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        #endif

        .tint(.pixelAccent)
    }

    /// A tappable grid cell that presents the send popover (#0067) — the sole
    /// entry point since `GalleryDetailView` was retired in #0068. Factored
    /// out of the `ForEach` body (rather
    /// than inlined) because the combined `Button` + `.contextMenu` +
    /// `.popover` modifier chain made the surrounding `ForEach` closure too
    /// slow for the type checker to infer in one shot.
    ///
    /// Each cell gets its own derived `.popover(item:)` binding — a single
    /// popover attached once at the grid/`ScrollView` level would lose
    /// per-cell anchoring on macOS/iPad, and one shared binding across every
    /// visible cell would present whichever cell's id happened to match.
    @ViewBuilder
    private func galleryCellButton(for item: GalleryItem) -> some View {
        Button {
            selectedItem = item
        } label: {
            galleryCell(for: item)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                coordinator.togglePin(item)
            } label: {
                Label(
                    item.isPinned ? "Unpin" : "Pin",
                    systemImage: item.isPinned ? "pin.slash" : "pin"
                )
            }
            Button {
                renameText = item.originalName
                itemToRename = item
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            Button(role: .destructive) {
                itemToDelete = item
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .popover(item: Binding(
            get: { selectedItem?.id == item.id ? selectedItem : nil },
            set: { if $0 == nil { selectedItem = nil } }
        )) { boundItem in
            GallerySendPopoverView(item: boundItem, coordinator: coordinator)
                // iPhone (compact width) adapts this popover to a sheet
                // automatically — deliberately NOT forcing
                // `.presentationCompactAdaptation(.popover)`, since this
                // content is a full send surface (dropdown + preview + Send +
                // variants list) that a cramped iPhone popover bubble would clip.
                .presentationDragIndicator(.visible)
        }
    }

    /// A single gallery grid cell: a square, rounded thumbnail of the imported
    /// original with the item's name and variant count as compact captions.
    @ViewBuilder
    private func galleryCell(for item: GalleryItem) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            // Square thumbnail regardless of the source image's aspect ratio:
            // a clear square defines the cell's footprint, the image fills it
            // and is clipped to the card radius.
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    StoredImageView(
                        path: item.originalImagePath,
                        maxPixelSize: 540,
                        coordinator: coordinator
                    ) {
                        Image(systemName: "photo.fill")
                            .resizable()
                            .scaledToFit()
                            .padding(Theme.Spacing.xl)
                            .foregroundStyle(.secondary)
                    }
                }
                .background(.quaternary)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                // Pin badge: a small filled pin on a material circle so it
                // stays legible over any thumbnail (#0035).
                .overlay(alignment: .topTrailing) {
                    if item.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption)
                            .padding(Theme.Spacing.xs + 2)
                            .background(.ultraThinMaterial, in: Circle())
                            .shadow(radius: 1, y: 1)
                            .padding(Theme.Spacing.xs)
                    }
                }

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(item.originalName)
                    .font(.headline)
                    .lineLimit(1)
                Text("\(item.variants.count) variant\(item.variants.count != 1 ? "s" : "")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, Theme.Spacing.xs)
        }
        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }
}

#Preview {
    GalleryListView()
}
