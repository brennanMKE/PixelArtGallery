#!/bin/bash
#
# appcast-item.sh — Generate a ready-to-paste Sparkle appcast <item> from a DMG.
#
# Mounts the DMG read-only, reads the real CFBundleShortVersionString and
# CFBundleVersion from the app bundle inside, computes the byte length, and
# signs the DMG with Sparkle's sign_update (EdDSA key in the keychain under
# account "PixelArtGallery"). Every attribute is derived from the artifact so
# the appcast can never drift from what users actually download.
#
# Usage:
#   scripts/appcast-item.sh <path-to-dmg>
#
# Paste the printed <item> at the top of the items in website/appcast.xml
# (newest first) and fill in the <description> release notes.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

SPARKLE_ACCOUNT="PixelArtGallery"
DOWNLOAD_BASE_URL="https://pixelartgallery.sstools.co/downloads"
CHANGELOG_BASE_URL="https://pixelartgallery.sstools.co/changelog.html"
MINIMUM_SYSTEM_VERSION="15.0"

fail() {
  echo "" >&2
  echo "error: $1" >&2
  [ $# -gt 1 ] && echo "hint:  $2" >&2
  exit 1
}

[ $# -eq 1 ] || fail "usage: scripts/appcast-item.sh <path-to-dmg>"
DMG_PATH="$1"
[ -f "$DMG_PATH" ] || fail "DMG not found: $DMG_PATH"

# --------------------------------------------------------------------------
# Locate Sparkle's sign_update in the SPM binary artifacts (package .build
# first, then Xcode DerivedData).
# --------------------------------------------------------------------------

PKG_BIN="$REPO_ROOT/PixelArtGalleryKit/.build/artifacts/sparkle/Sparkle/bin/sign_update"
DERIVED_GLOB="$HOME/Library/Developer/Xcode/DerivedData/PixelArtGallery-*/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update"

SIGN_UPDATE=""
if [ -x "$PKG_BIN" ]; then
  SIGN_UPDATE="$PKG_BIN"
else
  for candidate in $DERIVED_GLOB; do
    if [ -x "$candidate" ]; then
      SIGN_UPDATE="$candidate"
      break
    fi
  done
fi
[ -n "$SIGN_UPDATE" ] \
  || fail "Sparkle's sign_update tool was not found. Probed:
  $PKG_BIN
  $DERIVED_GLOB" \
          "Build the app (or run 'swift build' in PixelArtGalleryKit) so SPM resolves the Sparkle binary artifact."

# --------------------------------------------------------------------------
# Mount the DMG read-only and read the app's real version values.
# --------------------------------------------------------------------------

MOUNT_POINT="$(mktemp -d /tmp/appcast-item.XXXXXX)"
detach() {
  hdiutil detach "$MOUNT_POINT" -quiet 2>/dev/null || true
  rmdir "$MOUNT_POINT" 2>/dev/null || true
}
trap detach EXIT

hdiutil attach -readonly -nobrowse -mountpoint "$MOUNT_POINT" "$DMG_PATH" -quiet \
  || fail "hdiutil could not attach $DMG_PATH (is it a valid DMG?)"

APP_PATH="$(find "$MOUNT_POINT" -maxdepth 1 -name '*.app' -print -quit)"
[ -n "$APP_PATH" ] || fail "no .app bundle found at the root of the mounted DMG ($DMG_PATH)."

INFO_PLIST="$APP_PATH/Contents/Info.plist"
[ -f "$INFO_PLIST" ] || fail "missing Info.plist inside $APP_PATH."

SHORT_VERSION="$(plutil -extract CFBundleShortVersionString raw -o - "$INFO_PLIST")" \
  || fail "could not read CFBundleShortVersionString from $INFO_PLIST"
BUILD_VERSION="$(plutil -extract CFBundleVersion raw -o - "$INFO_PLIST")" \
  || fail "could not read CFBundleVersion from $INFO_PLIST"

# --------------------------------------------------------------------------
# Byte length and EdDSA signature — both from the artifact itself.
# --------------------------------------------------------------------------

LENGTH="$(stat -f%z "$DMG_PATH")"

SIGN_OUTPUT="$("$SIGN_UPDATE" --account "$SPARKLE_ACCOUNT" "$DMG_PATH" 2>&1)" \
  || fail "sign_update failed for account '$SPARKLE_ACCOUNT': $SIGN_OUTPUT" \
          "If the key is missing, generate it once with: $(dirname "$SIGN_UPDATE")/generate_keys --account $SPARKLE_ACCOUNT"

# sign_update prints: sparkle:edSignature="..." length="..."
ED_SIGNATURE="$(echo "$SIGN_OUTPUT" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')"
[ -n "$ED_SIGNATURE" ] || fail "could not parse sparkle:edSignature from sign_update output: $SIGN_OUTPUT"

SIGNED_LENGTH="$(echo "$SIGN_OUTPUT" | sed -n 's/.*length="\([^"]*\)".*/\1/p')"
[ "$SIGNED_LENGTH" = "$LENGTH" ] \
  || fail "length mismatch: stat reports $LENGTH bytes but sign_update reports $SIGNED_LENGTH."

# --------------------------------------------------------------------------
# Assemble the item. The changelog anchor uses the marketing version with
# dots replaced by hyphens (e.g. 1.0.0 -> #v1-0-0), matching changelog.html.
# --------------------------------------------------------------------------

DMG_BASENAME="$(basename "$DMG_PATH")"
DOWNLOAD_URL="$DOWNLOAD_BASE_URL/$DMG_BASENAME"
CHANGELOG_URL="$CHANGELOG_BASE_URL#v${SHORT_VERSION//./-}"
PUB_DATE="$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')"

echo ""
echo "Paste this <item> at the top of the items in website/appcast.xml:"
echo ""
cat <<XML
    <item>
      <title>Pixel Art Gallery $SHORT_VERSION</title>
      <link>$CHANGELOG_URL</link>
      <pubDate>$PUB_DATE</pubDate>
      <sparkle:version>$BUILD_VERSION</sparkle:version>
      <sparkle:shortVersionString>$SHORT_VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$MINIMUM_SYSTEM_VERSION</sparkle:minimumSystemVersion>
      <description><![CDATA[ ]]></description>
      <enclosure
        url="$DOWNLOAD_URL"
        length="$LENGTH"
        type="application/octet-stream"
        sparkle:edSignature="$ED_SIGNATURE"/>
    </item>
XML
