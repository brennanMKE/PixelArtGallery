# Ship checklist — Pixel Art Gallery v1.0.0 (macOS)

The explicit gate for shipping v1.0.0. Every row must have its "Verified"
cell filled in (date + initials, or a link to evidence) before the release is
announced. Process details: [`scripts/RELEASE.md`](scripts/RELEASE.md) and
[`scripts/SPARKLE.md`](scripts/SPARKLE.md).

## Build & distribution gates

| # | What to check | Verified |
|---|---|---|
| B1 | `scripts/preflight.sh` runs all-green: builds + 92 package tests, version gates, Sparkle gates, sandbox/hardened-runtime gates, Developer ID cert present, `PixelArtGallery-notary` keychain profile present, `PAG_EC2_HOST`/`PAG_EC2_PATH`/`PAG_EC2_KEY` set with correct key permissions, clean tree. | |
| B2 | `MARKETING_VERSION = 1.0.0` in `Configuration/Build.xcconfig` only (no pbxproj override), committed as `Bump version to 1.0.0`. | |
| B3 | `scripts/release.sh` full run (user-run) produced `dist/PixelArtGallery-1.0.0.dmg`: signed, app and DMG both notarized and stapled. | |
| B4 | `scripts/verify-dmg.sh dist/PixelArtGallery-1.0.0.dmg` — all six checks PASS (DMG spctl, DMG staple, app deep codesign, Developer ID authority, app staple, Gatekeeper on a freshly quarantined copy). | |
| B5 | Gatekeeper-clean install on a Mac that has **never** seen the app: DMG downloaded via a browser (quarantined), mounted, dragged to /Applications, launches with no "unidentified developer"/"damaged" dialog. | |
| B6 | Sparkle update from a previous installed build actually downloads and applies: with an older build installed, "Check for Updates…" finds 1.0.0, downloads, installs, and relaunches. Note: this needs **two releases** (or a locally served appcast + a lower-versioned local build) — for the very first release, verify via the local-appcast route and re-verify for real at 1.0.1. | |
| B7 | Website deployed (`scripts/deploy-website.sh`, user-run) and the appcast is reachable at the exact `SUFeedURL` (`https://pixelartgallery.sstools.co/appcast.xml`), with the 1.0.0 item newest-first and the DMG downloadable from `downloads/`. | |
| B8 | Release notes present in both the appcast item's CDATA description and `website/changelog.html#v1-0-0`; repo tagged `v1.0.0`. | |

## Functional sanity matrix

Run against the release build (the stapled app out of the DMG), not a debug
build.

| # | What to check | Verified |
|---|---|---|
| F1 | Import an image via the file picker on macOS; the naming step appears and the chosen name is applied to the new gallery item. | |
| F2 | Gallery grid shows items with thumbnails; pinning an item works and pinned items sort ahead as expected. | |
| F3 | Create a variant with the dimension sheet (custom target dimensions); edit an existing variant's dimensions; duplicate a variant; delete a variant. | |
| F4 | Pixel preview fits the view at the correct aspect ratio; zoom, pan, and single-pixel select all work. | |
| F5 | Export a variant as PNG — file is written and opens correctly. | |
| F6 | Export a variant as HEIC — file is written and opens correctly. | |
| F7 | Export a variant as PPM — file is written and opens correctly. | |
| F8 | Export a variant as JSON — file is written and matches the variant's grid. | |
| F9 | Send a variant to a Flaschen Taschen display; the default display works, and the display picker preselects the expected display. | |
| F10 | Display registry: mDNS scan discovers displays; manual add works; rename and delete of a registered display work. | |
| F11 | Settings: edit the default display and restore it back to defaults. | |
| F12 | Rename and delete gallery items (and confirm files/variants clean up with the item). | |
| F13 | Window respects its minimum size (640×480) and the default size (1000×700) on first launch. | |
| F14 | Whole app is presentable in both light and dark appearance (gallery, detail, variant, settings, sheets). | |
| F15 | "Check for Updates…" menu item is enabled (feed URL configured) and opens Sparkle's UI without errors. | |

## Known limitations (accepted for v1.0.0)

- **iOS ships later, separately.** v1.0.0 is macOS-only; the iOS build exists
  and must keep compiling (preflight gates it) but is not part of this
  release.
- **No Photos-library import on macOS** — import is via the file picker only.
- **The appcast is empty until the first release** — new installs before
  1.0.0's item lands will report "You're up to date."
- **English-only** — no localization in v1.0.0.
