# Pixel Art Gallery

A macOS/iOS SwiftUI app that imports images, pixelates them into variants at custom target dimensions, organizes them in a persistent gallery (SwiftData), and exports or sends variants to Flaschen Taschen (FT) network displays discovered via mDNS. The app target is `PixelArtGallery`; nearly all logic lives in the local Swift package `PixelArtGalleryKit`. Issues here track the work needed to bring the build up to the MVP defined in `PRD.md`, plus any bugs found along the way.

This file is the local guide for managing issues in this project. The companion Mac app (Issues.app) watches the `issues/` folder and renders the current state. Markdown files (and `project.json`) are the source of truth — there is no generated artifact or index to keep in sync.

The `# Pixel Art Gallery` heading above matches the `name` field in `issues/project.json`, which is the canonical source for the project's identity (name + repo URL).

## Status values

| File value | Display name | Meaning |
|---|---|---|
| `open` | Open | Filed but not yet started |
| `in-progress` | In Progress | Actively being worked on |
| `resolved` | Resolved | Work is done; awaiting user confirmation |
| `closed` | Closed | User has confirmed the fix |
| `wontfix` | Won't Fix | Acknowledged but won't be addressed |

Use the **file value** (lowercase, hyphenated) in the issue's metadata table.

## Critical rule: never close without explicit confirmation

An issue must **never** be marked `resolved`, `closed`, or `wontfix` based on inference — only when the user says so in plain language. A subagent that finishes a task may set `resolved`; only the user moves an issue to `closed`. When in doubt, leave it `open`/`in-progress` and ask.

## Git tracking

`issues/` is **tracked** in this repo, so each lifecycle event produces its own commit:

| Event | Commit message |
|---|---|
| File a new issue | `#NNNN <issue title>` |
| Resolve — code commit | `#NNNN <verb> <title>` |
| Resolve — resolution commit | `#NNNN Resolve: <title>` |
| Bail with notes | `#NNNN Notes: <brief>` |
| User-confirmed close | `#NNNN Close` |
| Won't fix | `#NNNN Won't fix` |

Setting status to `in-progress` at the start of work is a working-copy-only edit — not committed on its own.

## Build / verify command for this project

- **Package (unit tests):** `cd PixelArtGalleryKit && swift test`
- **App, macOS:** `xcodebuild -project PixelArtGallery.xcodeproj -scheme PixelArtGallery -destination 'platform=macOS' build`
- **App, iOS Simulator:** `xcodebuild -project PixelArtGallery.xcodeproj -scheme PixelArtGallery -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build`

A fix is only verified when the relevant command actually runs and tests/build pass — compilation alone is not verification. The app is multiplatform (iOS 18 / macOS 15); verify both platforms when a change touches platform-conditional code.

## Module conventions for this project

Use these canonical area names in the **Module** row:

- `App` — the `PixelArtGallery` app target (entry point, `ContentView`, `ModelContainer` setup)
- `Models` — SwiftData `@Model` types (`GalleryItem`, `Variant`, `FlaschenTaschenDisplay`)
- `Persistence` — `FileStorageManager` and SwiftData container/context wiring
- `ImageProcessing` — `PixelationEngine`, `PixelGrid`, `PixelColor`
- `ViewModels` — `GalleryCoordinator`, `PixelGridViewModel`
- `UI` — SwiftUI views in `PixelArtGalleryKit/Sources/PixelArtGalleryKit/UI`
- `Networking` — FT display mDNS discovery and the send client
- `Export` — variant exporters (PNG / HEIC / PPM / JSON) and Photos integration
- `Build` — project/build configuration, release pipeline scripts, signing/notarization
- `Website` — the static site (`website/`): landing page, changelog, appcast, downloads
- `Docs` — release documentation, checklists, project docs

## Issue format

Each issue is `NNNN.md` (4-digit zero-padded). Title separator is an em-dash (`—`). Metadata field names stay `**bold**`. Dates are `YYYY-MM-DD`. `Module` may list several separated by ` / `. `Platform` is `iOS`, `macOS`, or `All`. For feature-gap / task issues, a Description (plus Notes pointing at the relevant code) is enough — Steps/Expected/Actual are optional.
