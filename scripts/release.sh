#!/bin/bash
#
# release.sh — Developer ID release pipeline for PixelArtGallery (macOS).
#
# Pipeline: preflight -> archive -> export (Developer ID) -> codesign verify
#           -> notarize app -> staple app -> DMG -> sign DMG -> notarize DMG
#           -> staple DMG -> verify DMG.
#
# Usage:
#   scripts/release.sh              full release (submits to Apple's notary service)
#   scripts/release.sh --dry-run    stop after export + codesign verification;
#                                   never contacts Apple (alias: --skip-notarize)
#
# One-time setup: scripts/setup-keys.sh (stores the PixelArtGallery-notary
# keychain profile used for notarization).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

SCHEME="PixelArtGallery"
PROJECT="$REPO_ROOT/PixelArtGallery.xcodeproj"
CONFIGURATION="Release"
TEAM_ID="XV8BAAVZ6V"
NOTARY_PROFILE="PixelArtGallery-notary"
EXPORT_OPTIONS="$SCRIPT_DIR/ExportOptions.plist"
VOLUME_NAME="Pixel Art Gallery"

BUILD_DIR="$REPO_ROOT/build/release"
ARCHIVE_PATH="$BUILD_DIR/PixelArtGallery.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
DIST_DIR="$REPO_ROOT/dist"

DRY_RUN=0
for arg in "$@"; do
  case "$arg" in
    --dry-run|--skip-notarize) DRY_RUN=1 ;;
    -h|--help)
      sed -n '2,16p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "error: unknown argument '$arg' (supported: --dry-run | --skip-notarize)" >&2
      exit 2
      ;;
  esac
done

banner() {
  echo ""
  echo "==================================================================="
  echo "==> $1"
  echo "==================================================================="
}

fail() {
  echo "" >&2
  echo "error: $1" >&2
  [ $# -gt 1 ] && echo "hint:  $2" >&2
  exit 1
}

# Run an xcodebuild invocation quietly, logging to a file; on failure show the
# tail of the log so the actual compiler/signing error is visible.
run_logged() {
  local log="$1"; shift
  echo "\$ $*"
  echo "  (full log: $log)"
  if ! "$@" >"$log" 2>&1; then
    echo "" >&2
    tail -n 40 "$log" >&2
    fail "command failed: $1 (see full log at $log)"
  fi
}

# --------------------------------------------------------------------------
banner "Step 1/10: Preflight checks"
# --------------------------------------------------------------------------

command -v xcodebuild >/dev/null 2>&1 \
  || fail "xcodebuild not found." "Install Xcode and run: sudo xcode-select -s /Applications/Xcode.app"

[ -f "$EXPORT_OPTIONS" ] \
  || fail "missing $EXPORT_OPTIONS" "The export options plist should be committed alongside this script."

echo "Checking for a 'Developer ID Application' signing identity..."
IDENTITY_LIST="$(security find-identity -v -p codesigning)"
if ! echo "$IDENTITY_LIST" | grep -q "Developer ID Application"; then
  echo "$IDENTITY_LIST"
  fail "no 'Developer ID Application' certificate found in the keychain." \
       "Create one at https://developer.apple.com/account/resources/certificates (team $TEAM_ID) and install it, or download it via Xcode > Settings > Accounts > Manage Certificates."
fi
echo "$IDENTITY_LIST" | grep "Developer ID Application"

if [ "$DRY_RUN" -eq 1 ]; then
  echo "Dry run: skipping notary keychain-profile check (no network calls to Apple)."
else
  echo "Checking for the '$NOTARY_PROFILE' notary keychain profile..."
  if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" --output-format json >/dev/null 2>&1; then
    fail "notary keychain profile '$NOTARY_PROFILE' is missing or not working." \
         "Run scripts/setup-keys.sh once to store credentials (requires an app-specific Apple ID password)."
  fi
  echo "Notary profile OK."
fi

# --------------------------------------------------------------------------
banner "Step 2/10: Resolve versions"
# --------------------------------------------------------------------------

# Marketing version comes from build settings (kept in the project/xcconfig,
# see issue #0042) — never hard-coded here.
MARKETING_VERSION="$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" -destination 'generic/platform=macOS' \
    -showBuildSettings 2>/dev/null \
  | awk -F' = ' '/ MARKETING_VERSION = /{print $2; exit}')"
[ -n "$MARKETING_VERSION" ] \
  || fail "could not read MARKETING_VERSION from build settings." \
          "Check: xcodebuild -project PixelArtGallery.xcodeproj -scheme $SCHEME -showBuildSettings"

# Build number is derived from today's UTC date and injected at archive time.
BUILD_NUMBER="$(date -u +%Y%m%d)"

DMG_PATH="$DIST_DIR/PixelArtGallery-$MARKETING_VERSION.dmg"

echo "Marketing version:      $MARKETING_VERSION"
echo "Build number (UTC date): $BUILD_NUMBER"
echo "DMG output:             $DMG_PATH"

# --------------------------------------------------------------------------
banner "Step 3/10: Archive ($SCHEME, Release, macOS)"
# --------------------------------------------------------------------------

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

run_logged "$BUILD_DIR/archive.log" \
  xcodebuild archive \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE_PATH" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER"

[ -d "$ARCHIVE_PATH" ] || fail "archive failed: $ARCHIVE_PATH was not created."
echo "Archive OK: $ARCHIVE_PATH"

# --------------------------------------------------------------------------
banner "Step 4/10: Export with Developer ID signing"
# --------------------------------------------------------------------------

run_logged "$BUILD_DIR/export.log" \
  xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS" \
  -exportPath "$EXPORT_DIR"

APP_PATH="$EXPORT_DIR/PixelArtGallery.app"
[ -d "$APP_PATH" ] \
  || fail "export failed: $APP_PATH was not created." \
          "Check the xcodebuild -exportArchive output above; the Developer ID certificate (team $TEAM_ID) must be in the keychain."
echo "Export OK: $APP_PATH"

# --------------------------------------------------------------------------
banner "Step 5/10: Verify code signature"
# --------------------------------------------------------------------------

codesign --verify --deep --strict --verbose=2 "$APP_PATH" \
  || fail "codesign verification failed for $APP_PATH"

SIGN_INFO="$(codesign --display --verbose=2 "$APP_PATH" 2>&1)"
echo "$SIGN_INFO" | grep "Authority=" || true
if ! echo "$SIGN_INFO" | grep -q "Authority=Developer ID Application"; then
  fail "the exported app is not signed with a Developer ID Application certificate."
fi
echo "Signature OK (Developer ID Application, deep + strict)."

if [ "$DRY_RUN" -eq 1 ]; then
  banner "Dry run complete"
  echo "Archived, exported, and codesign-verified WITHOUT contacting Apple."
  echo ""
  echo "  App:             $APP_PATH"
  echo "  Build number:    $BUILD_NUMBER (CURRENT_PROJECT_VERSION, UTC date)"
  echo "  Marketing ver.:  $MARKETING_VERSION"
  echo ""
  echo "Skipped: notarization, stapling, DMG creation, and DMG verification."
  echo "Run scripts/release.sh (no flags) for the full release."
  echo ""
  echo "No DMG was produced, so no appcast item was generated. After a full"
  echo "release, run: scripts/appcast-item.sh $DMG_PATH"
  exit 0
fi

# --------------------------------------------------------------------------
banner "Step 6/10: Notarize the app (Apple notary service)"
# --------------------------------------------------------------------------

APP_ZIP="$BUILD_DIR/PixelArtGallery.zip"
ditto -c -k --keepParent "$APP_PATH" "$APP_ZIP"

echo "Submitting app to Apple's notary service (this can take a few minutes)..."
xcrun notarytool submit "$APP_ZIP" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait \
  || fail "app notarization failed." \
          "Inspect the log: xcrun notarytool log <submission-id> --keychain-profile $NOTARY_PROFILE"

# --------------------------------------------------------------------------
banner "Step 7/10: Staple the app"
# --------------------------------------------------------------------------

xcrun stapler staple "$APP_PATH" || fail "stapling the app failed."
echo "App stapled."

# --------------------------------------------------------------------------
banner "Step 8/10: Create DMG"
# --------------------------------------------------------------------------

mkdir -p "$DIST_DIR"
rm -f "$DMG_PATH"

DMG_STAGING="$BUILD_DIR/dmg-staging"
rm -rf "$DMG_STAGING"
mkdir -p "$DMG_STAGING"
cp -R "$APP_PATH" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"

hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$DMG_STAGING" \
  -ov -format UDZO \
  "$DMG_PATH" \
  || fail "hdiutil failed to create $DMG_PATH"
echo "DMG created: $DMG_PATH"

# --------------------------------------------------------------------------
banner "Step 9/10: Sign, notarize, and staple the DMG"
# --------------------------------------------------------------------------

codesign --sign "Developer ID Application" --timestamp "$DMG_PATH" \
  || fail "signing the DMG failed."

# The DMG needs its own notarization ticket before it can be stapled
# (the app inside is already notarized, so this pass is quick).
echo "Submitting DMG to Apple's notary service..."
xcrun notarytool submit "$DMG_PATH" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait \
  || fail "DMG notarization failed." \
          "Inspect the log: xcrun notarytool log <submission-id> --keychain-profile $NOTARY_PROFILE"

xcrun stapler staple "$DMG_PATH" || fail "stapling the DMG failed."
echo "DMG signed, notarized, and stapled."

# --------------------------------------------------------------------------
banner "Step 10/10: Verify the DMG"
# --------------------------------------------------------------------------

"$SCRIPT_DIR/verify-dmg.sh" "$DMG_PATH"

# --------------------------------------------------------------------------
banner "Release complete"
# --------------------------------------------------------------------------

echo "  DMG:             $DMG_PATH"
echo "  Marketing ver.:  $MARKETING_VERSION"
echo "  Build number:    $BUILD_NUMBER (CURRENT_PROJECT_VERSION, derived from UTC date)"
echo ""
echo "Next steps:"
echo "  1. Test-install on a clean Mac (download via a browser so it is quarantined)."
echo "  2. Upload $DMG_PATH to the website downloads (see website/, issue tracker)."
echo "  3. Tag the release: git tag v$MARKETING_VERSION-$BUILD_NUMBER"

# --------------------------------------------------------------------------
banner "Appcast item (website/appcast.xml)"
# --------------------------------------------------------------------------

"$SCRIPT_DIR/appcast-item.sh" "$DMG_PATH"
