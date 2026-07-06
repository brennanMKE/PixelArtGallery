# Downloads

Versioned DMGs (`PixelArtGallery-<X.Y.Z>.dmg`) land in this folder via the
release flow (see `scripts/release.sh` and issue #0041). They are large
binaries, so they are not committed as part of ordinary website changes —
whether a given DMG is committed or only uploaded at deploy time is the
release flow's call.

The landing page's Download button points at the latest
`PixelArtGallery-<X.Y.Z>.dmg` here, and every appcast item's enclosure URL
resolves into this folder.
