#!/bin/bash
#
# verify-dmg.sh — independently verify a PixelArtGallery release DMG.
#
# Usage: scripts/verify-dmg.sh <path-to-dmg>
#
# Checks (each reported pass/fail; exit is nonzero if any fail):
#   1. DMG signature            spctl --assess --type open --context context:primary-signature
#   2. DMG notarization ticket  stapler validate <dmg>
#   3. App deep signature       codesign --verify --deep --strict
#   4. App Developer ID chain   codesign --display Authority check
#   5. App notarization ticket  stapler validate <app>
#   6. Gatekeeper acceptance    spctl --assess --type execute on a quarantined copy

set -euo pipefail

if [ $# -ne 1 ]; then
  echo "usage: $0 <path-to-dmg>" >&2
  exit 2
fi

DMG_PATH="$1"
[ -f "$DMG_PATH" ] || { echo "error: no such file: $DMG_PATH" >&2; exit 2; }

MOUNT_POINT=""
WORK_DIR=""

cleanup() {
  if [ -n "$MOUNT_POINT" ] && [ -d "$MOUNT_POINT" ]; then
    hdiutil detach "$MOUNT_POINT" -quiet || true
  fi
  [ -n "$WORK_DIR" ] && rm -rf "$WORK_DIR"
}
trap cleanup EXIT

banner() {
  echo ""
  echo "==================================================================="
  echo "==> $1"
  echo "==================================================================="
}

FAILURES=0
PASS_LIST=()
FAIL_LIST=()

check() {
  # check <label> <command...>
  local label="$1"; shift
  echo ""
  echo "--- $label"
  echo "\$ $*"
  local output
  if output="$("$@" 2>&1)"; then
    [ -n "$output" ] && echo "$output"
    echo "PASS: $label"
    PASS_LIST+=("$label")
  else
    [ -n "$output" ] && echo "$output"
    echo "FAIL: $label"
    FAIL_LIST+=("$label")
    FAILURES=$((FAILURES + 1))
  fi
}

check_app_authority() {
  local app="$1"
  echo ""
  echo "--- App is signed with a Developer ID Application certificate"
  local info
  info="$(codesign --display --verbose=2 "$app" 2>&1)" || true
  echo "$info" | grep "Authority=" || echo "$info"
  if echo "$info" | grep -q "Authority=Developer ID Application"; then
    echo "PASS: App is signed with a Developer ID Application certificate"
    PASS_LIST+=("App Developer ID authority")
  else
    echo "FAIL: App is signed with a Developer ID Application certificate"
    FAIL_LIST+=("App Developer ID authority")
    FAILURES=$((FAILURES + 1))
  fi
}

banner "Verifying DMG: $DMG_PATH"

# --- Checks on the DMG itself -----------------------------------------------

check "DMG signature accepted (spctl, primary-signature)" \
  spctl --assess --type open --context context:primary-signature --verbose=4 "$DMG_PATH"

check "DMG notarization ticket stapled (stapler validate)" \
  xcrun stapler validate "$DMG_PATH"

# --- Mount and locate the app -----------------------------------------------

banner "Mounting DMG"

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/verify-dmg.XXXXXX")"
MOUNT_POINT="$WORK_DIR/mount"
mkdir -p "$MOUNT_POINT"

if ! hdiutil attach "$DMG_PATH" -mountpoint "$MOUNT_POINT" -nobrowse -readonly -quiet; then
  echo "error: could not mount $DMG_PATH" >&2
  MOUNT_POINT=""
  exit 1
fi

APP_IN_DMG="$(find "$MOUNT_POINT" -maxdepth 1 -name '*.app' -print -quit)"
if [ -z "$APP_IN_DMG" ]; then
  echo "error: no .app bundle found at the top level of the DMG" >&2
  exit 1
fi
echo "Found app: $APP_IN_DMG"

# --- Checks on the app inside the DMG ----------------------------------------

check "App code signature valid (codesign --verify --deep --strict)" \
  codesign --verify --deep --strict --verbose=2 "$APP_IN_DMG"

check_app_authority "$APP_IN_DMG"

check "App notarization ticket stapled (stapler validate)" \
  xcrun stapler validate "$APP_IN_DMG"

# --- Gatekeeper assessment under a fresh quarantine attribute ----------------

banner "Gatekeeper assessment on a quarantined copy"

QUARANTINED_APP="$WORK_DIR/$(basename "$APP_IN_DMG")"
ditto "$APP_IN_DMG" "$QUARANTINED_APP"
# Simulate a fresh browser download: 0181 = quarantined, user never approved.
xattr -w com.apple.quarantine "0181;$(printf '%x' "$(date +%s)");verify-dmg;" "$QUARANTINED_APP"
echo "Applied fresh com.apple.quarantine xattr to: $QUARANTINED_APP"

check "Gatekeeper accepts quarantined app (spctl --assess --type execute)" \
  spctl --assess --type execute --verbose=4 "$QUARANTINED_APP"

# --- Summary ------------------------------------------------------------------

banner "Summary"

for item in "${PASS_LIST[@]+"${PASS_LIST[@]}"}"; do
  echo "  PASS  $item"
done
for item in "${FAIL_LIST[@]+"${FAIL_LIST[@]}"}"; do
  echo "  FAIL  $item"
done

echo ""
if [ "$FAILURES" -gt 0 ]; then
  echo "RESULT: FAIL ($FAILURES check(s) failed) — this DMG is NOT ready to ship."
  exit 1
fi
echo "RESULT: PASS — signature, notarization, stapling, and Gatekeeper all OK."
