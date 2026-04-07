# Pixel Art Gallery - Product Requirements Document

## Overview
A macOS/iOS application that transforms images into pixel art and organizes them in a persistent gallery. Each gallery item stores the original image along with multiple pixelated variants at different target dimensions. The app integrates mDNS discovery to find Flaschen Taschen (FT) displays on the local network and stores them for easy selection when creating variants. Variants can be exported in multiple formats and sent directly to FT displays.

## Core Features

### 1. Image Import & Gallery Storage
- **Image Selection**: User selects images to add to the gallery
- **Persistent Storage**: Gallery stores original images with metadata (import date, filename, dimensions)
- **Gallery View**: Display gallery items with original image preview
- **Duplicate Prevention**: Option to skip importing images already in gallery

### 2. Pixelation & Variants
- **Create Variants**: User can pixelate the same original image at multiple target dimensions
- **Variant Storage**: Each gallery item maintains a list of variants with:
  - Original image reference
  - Target width and height (pixels)
  - Generated pixelated image data
  - Metadata (creation date, export format, scale factor, associated FT display if any)
- **Variant Management**: View, edit dimensions, delete, or duplicate variants within a gallery item
- **Batch Variant Creation**: Create variants for multiple discovered FT displays at once

### 3. Flaschen Taschen Integration
#### Discovery
- **mDNS Service Discovery**: Scan local network for FT displays (`_flaschen-taschen._tcp` or similar)
- **Display Information**: Extract endpoint (host/port), display width, height from discovery
- **Persistent Display Registry**: Store discovered displays with user-friendly names
- **Manual Display Entry**: Allow manual host/port entry if mDNS discovery fails

#### Send to FT
- **Direct Send**: Send pixelated variants to stored FT displays
- **Dimension Matching**: Use discovered FT display dimensions as suggested target dimensions for new variants
- **Send Status**: Show progress and success/error feedback

### 4. Export
- **Export Formats**:
  - PNG image
  - HEIC image
  - PPM (raw pixel format)
  - JSON (color matrix data)
- **Export Destination**: Save to file or Photos app (iOS only)
- **Variant Scaling**: Support configurable pixel scale factor for exports

### 5. Color Sampling & Display
- **Downsampling Algorithm**: Bilinear interpolation with light blur (same as PixelArtConverter)
- **Grid Rendering**: Use SwiftUI Canvas for efficient pixel grid display
- **Color Accuracy**: Preserve accurate RGB values from source image
- **Interactive Grid**: Hover/tap to view pixel color values

## User Workflow

### Typical Session
1. Launch app
2. Import one or more images into gallery
3. (Optional) Discover local FT displays via mDNS scan
4. Select a gallery item (original image)
5. Create variant(s):
   - Option A: Use discovered FT display dimensions
   - Option B: Enter custom width/height
6. Preview pixelated result
7. Export and/or send to FT display
8. Browse gallery to revisit/modify past variants

### Alternative Workflow (Batch FT Creation)
1. Import image
2. Trigger "Create Variants for All FT Displays"
3. App automatically creates variants at each display's native dimensions
4. Browse gallery to review generated variants
5. Send any variant to its associated display or another display

## Data Model

### GalleryItem
- `id`: Unique identifier
- `originalImage`: CGImage data (or file reference)
- `originalName`: Filename of imported image
- `importedDate`: Timestamp
- `variants`: Array of Variant

### Variant
- `id`: Unique identifier
- `galleryItemId`: Reference to parent GalleryItem
- `targetWidth`: Pixel width
- `targetHeight`: Pixel height
- `pixelGridData`: Rasterized image (or reference)
- `createdDate`: Timestamp
- `exportFormat`: Last used format (PNG, HEIC, PPM, JSON)
- `associatedDisplayId`: Optional reference to FT display (if auto-created)
- `scaleFactor`: Pixel scale for display/export

### FlaschenTaschenDisplay
- `id`: Unique identifier
- `host`: Hostname or IP address
- `port`: Service port
- `displayName`: User-friendly name
- `displayWidth`: Native pixel width
- `displayHeight`: Native pixel height
- `discoveredDate`: Timestamp
- `source`: `manual` or `mdns`

## Technical Architecture

### Platform & Environment
- **Primary**: macOS 12.0+ (SwiftUI, Foundation)
- **Secondary**: iOS support (same app, adapted UI for smaller screens)
- **Persistence**: SwiftData for modern data layer

### State Management
- **Observable Pattern**: Use `@Observable` for all view models (never `ObservableObject`)
- **Actor Isolation**: Default `@MainActor` for UI models and coordinators
- **Background Processing**: Image processing and mDNS operations in `actor` or `nonisolated` functions
- **Swift Concurrency**: Modern async/await, no Combine or Dispatch

### Image Processing
- **Image Loading**: Use `CGImageSource` (ImageIO framework) for robust format support
- **Pixel Data**: Extract to RGB `[UInt8]` arrays
- **Downsampling**: Bilinear interpolation + light blur (reference: PixelArtConverter architecture)
- **Background Actor**: Wrap intensive operations to prevent UI blocking

### Grid Rendering
- **Canvas-Based**: Use SwiftUI Canvas for efficient rendering (not individual Rectangle views)
- **Performance**: Single Canvas redraws on observable mutation
- **Scalability**: Monitor performance with grids 500×500+

### mDNS Discovery
- **Framework**: Use `Network.framework` or equivalent (macOS/iOS compatible)
- **Service Type**: Search for `_flaschen-taschen._tcp` (or custom service name)
- **Polling Strategy**: On-demand scan vs. background continuous discovery (TBD)
- **Error Handling**: Graceful fallback to manual entry if discovery unavailable

### Data Persistence
- **SwiftData Models**: GalleryItem, Variant, FlaschenTaschenDisplay
- **Image Storage**: Determine strategy—file-based (~/Library/Application Support) or embedded
- **Sync**: No cloud sync required for MVP

### Logging
- **Structured Logging**: Use `os.log` (unified logging system)
- **Categories**: `Gallery`, `ImageProcessor`, `Variant`, `FTDiscovery`, `Export`, `GridRenderer`
- **Levels**: `debug` for tracing, `info` for events, `warning`/`error` for issues

### Export & Send
- **Export Model**: Reuse/adapt from PixelArtConverter (JSON, PPM, HEIC, PNG generation)
- **FT Client**: Use ft-swift library (already in PixelArtConverter) for sending images
- **Network**: Send via stored FT host/port from discovery or manual entry

## MVP Scope

### Must Have
- [x] Import images into persistent gallery
- [x] Store original + variants for each gallery item
- [x] Create variants at custom target dimensions
- [x] Display pixelated grid with accurate colors
- [x] Zoom controls on grid view
- [x] Export variants (PNG, HEIC, PPM, JSON)
- [x] mDNS discovery of FT displays
- [x] Send variants to discovered/stored FT displays
- [x] Persistent storage of discovered FT displays

### Nice to Have (Post-MVP)
- Aspect ratio lock when setting variant dimensions
- Batch variant creation for all discovered FT displays
- Variant editing/deletion UI
- Gallery search and filtering
- Color palette extraction from images
- Undo/Redo for variant creation
- Drag & drop image import
- Cloud sync of gallery (future)

### Out of Scope (MVP)
- Animated GIF frame-by-frame processing
- Advanced color grading or filters
- Dithering or special effects
- Multi-user collaboration
- Version control for variants

## Success Criteria
- User can import an image, create a pixelated variant, and send to FT display in under 30 seconds
- Gallery displays all items and variants with correct metadata
- mDNS discovery finds FT displays reliably on local network
- Pixelated output maintains color accuracy
- App remains responsive with grids up to 500×500 pixels
- Imported images and variants persist across app launches

## Open Questions
1. Should gallery support grouping variants (e.g., by FT display or creation date)?
2. What is the maximum number of gallery items/variants expected?
3. Should variants auto-update if original image is updated?
4. Do we need variant versioning (e.g., "v1", "v2" of same dimensions)?
5. Should the app support WebDAV or other remote FT discovery?
