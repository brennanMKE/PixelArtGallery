# Sparkle auto-updates: keys, wiring, and per-release signing

Companion to [`RELEASE.md`](RELEASE.md). Everything Sparkle-specific lives
here: how the integration is wired into the app, where the EdDSA key lives,
the exact tool invocations, and the per-release appcast-item flow.

## How the integration is wired

- **Dependency** — `sparkle-project/Sparkle` 2.x via SPM in
  `PixelArtGalleryKit/Package.swift`, attached to the Kit target with
  `.product(name: "Sparkle", package: "Sparkle", condition: .when(platforms: [.macOS]))`.
  The iOS build never links or embeds Sparkle (preflight has a gate for
  this). `Package.resolved` pins the version and is committed.
- **Controller** —
  `PixelArtGalleryKit/Sources/PixelArtGalleryKit/UpdaterController.swift`
  (`#if os(macOS) && canImport(Sparkle)`) wraps `SPUStandardUpdaterController`.
  It is created with `startingUpdater: false` and calls `startUpdater()`
  **only when configured** (`SUFeedURL` present and non-empty in
  `Bundle.main`); unconfigured, `checkForUpdates()` is a logged no-op
  (`AppLog.updates`) and the menu item is disabled. Starting an unconfigured
  updater would surface Sparkle's automatic-check permission prompt and later
  feed errors.
- **Menu** — `PixelArtGallery/PixelArtGalleryApp.swift` adds a macOS-only
  `Commands` block replacing `.appInfo`: "About Pixel Art Gallery" plus
  "Check for Updates…" invoking `UpdaterController.shared.checkForUpdates()`.
- **Info.plist keys** — the macOS build uses a real plist file,
  `PixelArtGallery/Info-macOS.plist` (iOS keeps its generated plist), which
  carries:
  - `SUFeedURL` = `https://pixelartgallery.sstools.co/appcast.xml`
  - `SUPublicEDKey` = `tQZNcNn4+PYvilca5jBXoPx6XHxM6mCYrwWh3pzl+H0=`
  - `SUEnableAutomaticChecks` = `true`
- **Update comparison** — Sparkle compares `sparkle:version`
  (`CFBundleVersion`), which `scripts/release.sh` sets to the UTC date
  (`YYYYMMDD`) at archive time, so it is always monotonically increasing.
  `sparkle:shortVersionString` (= `MARKETING_VERSION`) is display-only.

## Where the Sparkle helper tools live

`generate_keys`, `sign_update`, `generate_appcast`, and `BinaryDelta` are
shipped in Sparkle's SPM binary artifact. After any build that resolves the
package they exist at **both**:

- `PixelArtGalleryKit/.build/artifacts/sparkle/Sparkle/bin/`
  (from `swift build` / `swift test` in the package)
- `~/Library/Developer/Xcode/DerivedData/PixelArtGallery-*/SourcePackages/artifacts/sparkle/Sparkle/bin/`
  (from `xcodebuild`)

`scripts/appcast-item.sh` probes the package path first, then the DerivedData
glob. If neither exists, run `swift build` in `PixelArtGalleryKit` once.

## The EdDSA key (account `PixelArtGallery`)

The private key lives **only in this Mac's login keychain**, under keychain
account `PixelArtGallery` — never in the repo. Every invocation below must
pass `--account PixelArtGallery`; the tools' default account name will not
find the key ("Signing key not found"). Losing the private key means shipped
apps can never verify another update, so keep an offline backup.

All commands below assume the Sparkle bin directory (above) is on `PATH` or
prefixed explicitly.

```sh
# Print the public key for the existing keypair (sanity check — must match
# SUPublicEDKey in PixelArtGallery/Info-macOS.plist):
generate_keys -p --account PixelArtGallery

# BACKUP the private key to an offline file (do this once; store offline):
generate_keys -x /path/to/offline-backup/pixelartgallery-eddsa.key --account PixelArtGallery

# RESTORE the private key into a new machine's keychain from the backup:
generate_keys -f /path/to/offline-backup/pixelartgallery-eddsa.key --account PixelArtGallery

# Generate a brand-new keypair — ONLY for a machine/product with no shipped
# builds. Never re-generate for this app: the new public key would not match
# the SUPublicEDKey embedded in installed apps, permanently breaking updates.
generate_keys --account PixelArtGallery

# Sign a release artifact (what appcast-item.sh runs for you):
sign_update --account PixelArtGallery dist/PixelArtGallery-<X.Y.Z>.dmg
```

**Keychain ACL prompt:** the first `sign_update` run from a given binary path
triggers a macOS keychain authorization dialog and the tool appears to hang
until you click "Always Allow". The prompt recurs once per binary path — the
package `.build` copy and the DerivedData copy are separate binaries.

## Per-release: generating the appcast item

```sh
scripts/appcast-item.sh dist/PixelArtGallery-<X.Y.Z>.dmg
```

(`scripts/release.sh` runs this automatically at the end of a full release.)

The script mounts the DMG read-only, reads the real
`CFBundleShortVersionString` / `CFBundleVersion` from the app inside,
measures the byte length with `stat`, signs the DMG with
`sign_update --account PixelArtGallery`, cross-checks sign_update's reported
length against stat's, and prints a complete `<item>` — title, `<link>` to
`https://pixelartgallery.sstools.co/changelog.html#vX-Y-Z`, RFC 822
`<pubDate>`, `sparkle:version`, `sparkle:shortVersionString`,
`sparkle:minimumSystemVersion` (15.0), an empty `<description><![CDATA[ ]]>`
placeholder for release notes, and an `<enclosure>` with the
`https://pixelartgallery.sstools.co/downloads/<dmg-basename>` URL, `length`,
`type`, and `sparkle:edSignature`.

**Why derived, not hand-typed:** a hand-typed item invites drift — a
`sparkle:version` that doesn't match the DMG's real `CFBundleVersion`, a
stale length, or a signature over the wrong bytes produces broken
"You're up to date" behavior or failed signature verification on every
client while the appcast claims a newer version exists. Deriving every
attribute from the artifact itself makes that class of failure impossible.

Paste the item into `website/appcast.xml` above existing items (newest
first), fill in the CDATA release notes, copy the DMG to
`website/downloads/`, and re-run `scripts/preflight.sh` — its website gate
re-mounts the DMG and verifies the appcast advertises exactly what the file
contains.
