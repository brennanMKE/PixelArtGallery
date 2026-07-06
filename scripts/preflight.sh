#!/bin/bash
#
# preflight.sh — Run every release-readiness gate in one pass (#0043).
#
# Answers "is this shippable right now?" in one command. Each gate prints
# [✓] pass, [✗] fail (with the command that fixes it), [!] warning, or
# [-] skipped. Exits nonzero if any gate fails.
#
# Gates:
#   Build    — macOS build, package tests (with observed test count), iOS build
#   Version  — MARKETING_VERSION only in Configuration/Build.xcconfig (#0042),
#              SemVer format, strictly greater than the newest appcast version
#   Sparkle  — dependency in Package.swift, production feed configured for the
#              Release configuration, SUPublicEDKey in the built macOS app and
#              NO production SUFeedURL in the built Debug/beta app (#0045),
#              NO Sparkle inside the built iOS app (#0038/#0039)
#   Identity — Release configuration carries the production bundle ID and
#              Debug the .beta one (#0045)
#   Sandbox  — no com.apple.security.app-sandbox entitlement, hardened runtime on (#0036)
#   Signing  — Developer ID Application cert, PixelArtGallery-notary profile (#0037)
#   Website  — PAG_EC2_* env vars + SSH key perms (#0040), appcast<->DMG consistency (#0041)
#   Hygiene  — clean working tree
#
# Usage:
#   scripts/preflight.sh                 all gates, including builds (slow)
#   scripts/preflight.sh --skip-build    skip build/test gates; probe the last
#                                        preflight build products if present
#   scripts/preflight.sh --strict        warnings count as failures
#   scripts/preflight.sh --allow-dirty   don't fail on a dirty working tree
#
# Builds use a fixed derived-data path (build/preflight) so the built-product
# gates always inspect the artifacts this script just produced.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PROJECT="$REPO_ROOT/PixelArtGallery.xcodeproj"
SCHEME="PixelArtGallery"
PACKAGE_DIR="$REPO_ROOT/PixelArtGalleryKit"
XCCONFIG="$REPO_ROOT/Configuration/Build.xcconfig"
PBXPROJ="$PROJECT/project.pbxproj"
APPCAST="$REPO_ROOT/website/appcast.xml"
DOWNLOADS_DIR="$REPO_ROOT/website/downloads"
NOTARY_PROFILE="PixelArtGallery-notary"
IOS_DESTINATION="platform=iOS Simulator,name=iPhone 17 Pro"

DERIVED_DATA="$REPO_ROOT/build/preflight"
MACOS_APP="$DERIVED_DATA/Build/Products/Debug/PixelArtGallery.app"
IOS_APP="$DERIVED_DATA/Build/Products/Debug-iphonesimulator/PixelArtGallery.app"
LOG_DIR="$DERIVED_DATA/logs"

SKIP_BUILD=0
STRICT=0
ALLOW_DIRTY=0
for arg in "$@"; do
  case "$arg" in
    --skip-build)  SKIP_BUILD=1 ;;
    --strict)      STRICT=1 ;;
    --allow-dirty) ALLOW_DIRTY=1 ;;
    -h|--help)
      sed -n '2,32p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "error: unknown argument '$arg' (supported: --skip-build | --strict | --allow-dirty)" >&2
      exit 2
      ;;
  esac
done

PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0
SKIP_COUNT=0

section() {
  echo ""
  echo "--- $1 ---"
}

pass() { # pass <message>
  printf '[✓] %s\n' "$1"
  PASS_COUNT=$((PASS_COUNT + 1))
}

gate_fail() { # gate_fail <message> [fix]
  printf '[✗] %s\n' "$1"
  [ $# -gt 1 ] && printf '    fix: %s\n' "$2"
  FAIL_COUNT=$((FAIL_COUNT + 1))
}

warn() { # warn <message> [fix] — becomes a failure under --strict
  if [ "$STRICT" -eq 1 ]; then
    printf '[✗] %s (warning promoted by --strict)\n' "$1"
    [ $# -gt 1 ] && printf '    fix: %s\n' "$2"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  else
    printf '[!] %s\n' "$1"
    [ $# -gt 1 ] && printf '    fix: %s\n' "$2"
    WARN_COUNT=$((WARN_COUNT + 1))
  fi
}

skip() { # skip <message>
  printf '[-] %s (skipped)\n' "$1"
  SKIP_COUNT=$((SKIP_COUNT + 1))
}

# ver_gt A B — true if SemVer A is strictly greater than B.
ver_gt() {
  [ "$1" = "$2" ] && return 1
  [ "$(printf '%s\n%s\n' "$1" "$2" | sort -t. -k1,1n -k2,2n -k3,3n | tail -1)" = "$1" ]
}

echo "PixelArtGallery release preflight ($(date '+%Y-%m-%d %H:%M:%S'))"
[ "$SKIP_BUILD" -eq 1 ] && echo "(--skip-build: build/test gates skipped; probing last build if present)"
[ "$STRICT" -eq 1 ] && echo "(--strict: warnings count as failures)"

mkdir -p "$LOG_DIR"

# ===========================================================================
section "Build gates"
# ===========================================================================

MACOS_BUILT=0
IOS_BUILT=0

if [ "$SKIP_BUILD" -eq 1 ]; then
  skip "macOS build"
  skip "package tests (swift test)"
  skip "iOS Simulator build"
  [ -d "$MACOS_APP" ] && MACOS_BUILT=1
  [ -d "$IOS_APP" ] && IOS_BUILT=1
else
  echo "Building macOS (log: $LOG_DIR/build-macos.log)..."
  if xcodebuild -project "$PROJECT" -scheme "$SCHEME" \
       -destination 'platform=macOS' \
       -derivedDataPath "$DERIVED_DATA" build \
       >"$LOG_DIR/build-macos.log" 2>&1; then
    pass "macOS build succeeds"
    MACOS_BUILT=1
  else
    tail -n 20 "$LOG_DIR/build-macos.log"
    gate_fail "macOS build failed (full log: $LOG_DIR/build-macos.log)" \
              "xcodebuild -project PixelArtGallery.xcodeproj -scheme $SCHEME -destination 'platform=macOS' build"
  fi

  echo "Running package tests (log: $LOG_DIR/swift-test.log)..."
  if (cd "$PACKAGE_DIR" && swift test) >"$LOG_DIR/swift-test.log" 2>&1; then
    # Both harnesses can run in one invocation: XCTest prints per-suite
    # "Executed N tests, with 0 failures" lines (the 'All tests' total is the
    # largest) and Swift Testing prints "Test run with N tests ... passed".
    XCTEST_COUNT="$(sed -nE 's/.*Executed ([0-9]+) tests?, with 0 failures.*/\1/p' "$LOG_DIR/swift-test.log" | sort -n | tail -1)"
    ST_COUNT="$(sed -nE 's/.*Test run with ([0-9]+) tests.*passed.*/\1/p' "$LOG_DIR/swift-test.log" | tail -1)"
    TEST_COUNT=$(( ${XCTEST_COUNT:-0} + ${ST_COUNT:-0} ))
    if [ "$TEST_COUNT" -gt 0 ]; then
      pass "package tests pass ($TEST_COUNT tests executed)"
    else
      gate_fail "swift test exited 0 but no executed-test count was found (log: $LOG_DIR/swift-test.log)" \
                "cd PixelArtGalleryKit && swift test  # confirm tests actually ran"
    fi
  else
    tail -n 20 "$LOG_DIR/swift-test.log"
    gate_fail "package tests failed (full log: $LOG_DIR/swift-test.log)" \
              "cd PixelArtGalleryKit && swift test"
  fi

  echo "Building iOS Simulator (log: $LOG_DIR/build-ios.log)..."
  if xcodebuild -project "$PROJECT" -scheme "$SCHEME" \
       -destination "$IOS_DESTINATION" \
       -derivedDataPath "$DERIVED_DATA" build \
       >"$LOG_DIR/build-ios.log" 2>&1; then
    pass "iOS Simulator build succeeds"
    IOS_BUILT=1
  else
    tail -n 20 "$LOG_DIR/build-ios.log"
    gate_fail "iOS Simulator build failed (full log: $LOG_DIR/build-ios.log)" \
              "xcodebuild -project PixelArtGallery.xcodeproj -scheme $SCHEME -destination '$IOS_DESTINATION' build"
  fi
fi

# ===========================================================================
section "Version gates"
# ===========================================================================

MARKETING_VERSION="$(sed -nE 's/^[[:space:]]*MARKETING_VERSION[[:space:]]*=[[:space:]]*([^[:space:]]+).*/\1/p' "$XCCONFIG" | head -1)"

if [ -z "$MARKETING_VERSION" ]; then
  gate_fail "MARKETING_VERSION not found in Configuration/Build.xcconfig" \
            "add 'MARKETING_VERSION = X.Y.Z' to Configuration/Build.xcconfig (#0042)"
else
  pass "MARKETING_VERSION = $MARKETING_VERSION in Configuration/Build.xcconfig"
fi

if grep -q "MARKETING_VERSION" "$PBXPROJ"; then
  gate_fail "MARKETING_VERSION appears in project.pbxproj — Build.xcconfig must be the single source (#0042)" \
            "remove every MARKETING_VERSION line from PixelArtGallery.xcodeproj/project.pbxproj"
else
  pass "no MARKETING_VERSION in project.pbxproj (xcconfig is the single source)"
fi

if [ -n "$MARKETING_VERSION" ]; then
  if [[ "$MARKETING_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    pass "version '$MARKETING_VERSION' is valid SemVer (X.Y.Z)"
  else
    gate_fail "version '$MARKETING_VERSION' is not SemVer (expected X.Y.Z)" \
              "fix MARKETING_VERSION in Configuration/Build.xcconfig"
  fi

  NEWEST_APPCAST_VERSION="$(sed -nE 's/.*<sparkle:shortVersionString>([^<]+)<\/sparkle:shortVersionString>.*/\1/p' "$APPCAST" | head -1)"
  if [ -z "$NEWEST_APPCAST_VERSION" ]; then
    pass "appcast has no published items yet — nothing to be greater than (note: first release)"
  elif ver_gt "$MARKETING_VERSION" "$NEWEST_APPCAST_VERSION"; then
    pass "version $MARKETING_VERSION > newest appcast version $NEWEST_APPCAST_VERSION"
  else
    gate_fail "version $MARKETING_VERSION is not greater than the newest appcast version $NEWEST_APPCAST_VERSION" \
              "bump MARKETING_VERSION in Configuration/Build.xcconfig above $NEWEST_APPCAST_VERSION"
  fi
fi

# ===========================================================================
section "Sparkle gates"
# ===========================================================================

if grep -q 'sparkle-project/Sparkle' "$PACKAGE_DIR/Package.swift"; then
  pass "Sparkle dependency present in PixelArtGalleryKit/Package.swift"
else
  gate_fail "Sparkle dependency missing from PixelArtGalleryKit/Package.swift" \
            "re-add .package(url: \"https://github.com/sparkle-project/Sparkle\", from: \"2.6.0\") (#0038)"
fi

# The production feed lives in the Release configuration only (#0045):
# PAG_SPARKLE_FEED_URL is substituted into SUFeedURL at build time, and Debug
# builds get an empty value so the beta never talks to the production feed.
RELEASE_FEED_URL="$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" \
    -configuration Release -destination 'generic/platform=macOS' -showBuildSettings 2>/dev/null \
  | awk -F' = ' '/ PAG_SPARKLE_FEED_URL = /{print $2; exit}')"
if [ -n "$RELEASE_FEED_URL" ]; then
  pass "Release configuration has PAG_SPARKLE_FEED_URL ($RELEASE_FEED_URL)"
else
  gate_fail "Release configuration has no PAG_SPARKLE_FEED_URL — released builds would ship without a Sparkle feed" \
            "restore PAG_SPARKLE_FEED_URL in the Release build settings (#0045)"
fi

if [ "$MACOS_BUILT" -eq 1 ]; then
  MAC_PLIST="$MACOS_APP/Contents/Info.plist"
  SU_FEED_URL="$(plutil -extract SUFeedURL raw -o - "$MAC_PLIST" 2>/dev/null || true)"
  SU_PUBLIC_KEY="$(plutil -extract SUPublicEDKey raw -o - "$MAC_PLIST" 2>/dev/null || true)"
  if [ -z "$SU_FEED_URL" ]; then
    pass "built Debug/beta macOS app has no production SUFeedURL (updater stays off, #0045)"
  else
    gate_fail "built Debug/beta macOS app has SUFeedURL ($SU_FEED_URL) — dev builds must not use the production feed" \
              "set PAG_SPARKLE_FEED_URL to empty in the Debug build settings (#0045), then rebuild"
  fi
  if [ -n "$SU_PUBLIC_KEY" ]; then
    pass "built macOS app has SUPublicEDKey"
  else
    gate_fail "built macOS app is missing SUPublicEDKey in Info.plist" \
              "restore the SUPublicEDKey wiring (#0039), then rebuild"
  fi
else
  skip "SUFeedURL/SUPublicEDKey in built macOS app — no build at $MACOS_APP"
fi

if [ "$IOS_BUILT" -eq 1 ]; then
  SPARKLE_IN_IOS="$(find "$IOS_APP" -iname '*sparkle*' -print -quit 2>/dev/null)"
  if [ -z "$SPARKLE_IN_IOS" ]; then
    pass "built iOS app contains no Sparkle (macOS-only dependency respected)"
  else
    gate_fail "built iOS app embeds Sparkle: $SPARKLE_IN_IOS" \
              "make the Sparkle dependency macOS-conditional in Package.swift (#0038)"
  fi
else
  skip "no-Sparkle-in-iOS check — no build at $IOS_APP"
fi

# ===========================================================================
section "Identity gates"
# ===========================================================================

# Release builds (what scripts/release.sh archives) must carry the production
# bundle ID; Debug builds carry the .beta identity so dev and shipped apps
# coexist with separate data (#0045).
PROD_BUNDLE_ID="co.sstools.PixelArtGallery"
BETA_BUNDLE_ID="co.sstools.PixelArtGallery.beta"

RELEASE_BUNDLE_ID="$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" \
    -configuration Release -destination 'generic/platform=macOS' -showBuildSettings 2>/dev/null \
  | awk -F' = ' '/ PRODUCT_BUNDLE_IDENTIFIER = /{print $2; exit}')"
if [ "$RELEASE_BUNDLE_ID" = "$PROD_BUNDLE_ID" ]; then
  pass "Release configuration bundle ID is $PROD_BUNDLE_ID"
else
  gate_fail "Release configuration bundle ID is '${RELEASE_BUNDLE_ID:-unset}' (expected $PROD_BUNDLE_ID)" \
            "fix PRODUCT_BUNDLE_IDENTIFIER in the target's Release build settings (#0045)"
fi

DEBUG_BUNDLE_ID="$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" \
    -configuration Debug -destination 'generic/platform=macOS' -showBuildSettings 2>/dev/null \
  | awk -F' = ' '/ PRODUCT_BUNDLE_IDENTIFIER = /{print $2; exit}')"
if [ "$DEBUG_BUNDLE_ID" = "$BETA_BUNDLE_ID" ]; then
  pass "Debug configuration bundle ID is $BETA_BUNDLE_ID"
else
  gate_fail "Debug configuration bundle ID is '${DEBUG_BUNDLE_ID:-unset}' (expected $BETA_BUNDLE_ID)" \
            "fix PRODUCT_BUNDLE_IDENTIFIER in the target's Debug build settings (#0045)"
fi

# ===========================================================================
section "Sandbox / hardened runtime gates"
# ===========================================================================

if [ "$MACOS_BUILT" -eq 1 ]; then
  ENTITLEMENTS="$(codesign -d --entitlements :- "$MACOS_APP" 2>/dev/null || true)"
  if echo "$ENTITLEMENTS" | grep -A1 'com.apple.security.app-sandbox' | grep -q '<true/>'; then
    gate_fail "built macOS app has com.apple.security.app-sandbox enabled — the direct-download build must be unsandboxed (#0036)" \
              "set ENABLE_APP_SANDBOX = NO / remove the sandbox entitlement, then rebuild"
  else
    pass "built macOS app has no app-sandbox entitlement (unsandboxed, per #0036)"
  fi
else
  skip "app-sandbox entitlement check — no build at $MACOS_APP"
fi

HARDENED="$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" \
    -destination 'generic/platform=macOS' -showBuildSettings 2>/dev/null \
  | awk -F' = ' '/ ENABLE_HARDENED_RUNTIME = /{print $2; exit}')"
if [ "$HARDENED" = "YES" ]; then
  pass "ENABLE_HARDENED_RUNTIME = YES (macOS build settings)"
else
  gate_fail "ENABLE_HARDENED_RUNTIME is '${HARDENED:-unset}' — hardened runtime is required for notarization (#0036)" \
            "set ENABLE_HARDENED_RUNTIME = YES in the macOS build configuration"
fi

# ===========================================================================
section "Signing gates"
# ===========================================================================

if security find-identity -v -p codesigning 2>/dev/null | grep -q "Developer ID Application"; then
  pass "'Developer ID Application' certificate present in the keychain"
else
  gate_fail "no 'Developer ID Application' certificate in the keychain" \
            "install one via Xcode > Settings > Accounts > Manage Certificates, or https://developer.apple.com/account/resources/certificates"
fi

NOTARY_OUTPUT="$(xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" --output-format json 2>&1)"
NOTARY_STATUS=$?
if [ "$NOTARY_STATUS" -eq 0 ]; then
  pass "notary keychain profile '$NOTARY_PROFILE' works (notarytool history OK)"
elif echo "$NOTARY_OUTPUT" | grep -qiE 'keychain|password item|profile'; then
  gate_fail "notary keychain profile '$NOTARY_PROFILE' is missing from the keychain" \
            "run scripts/setup-keys.sh once to store the notarization credentials"
else
  # Credentials may exist but Apple's service was unreachable — warn, don't fail.
  warn "notarytool history failed for '$NOTARY_PROFILE' (possible network issue): $(echo "$NOTARY_OUTPUT" | head -1)" \
       "check connectivity, or re-run scripts/setup-keys.sh if credentials expired"
fi

# ===========================================================================
section "Website gates"
# ===========================================================================

ENV_OK=1
for var in PAG_EC2_HOST PAG_EC2_PATH PAG_EC2_KEY; do
  if [ -z "${!var:-}" ]; then
    gate_fail "$var is not set — website deploy (#0040) will fail" \
              "export $var (see scripts/deploy-website.sh --help for examples)"
    ENV_OK=0
  fi
done
if [ "$ENV_OK" -eq 1 ]; then
  pass "PAG_EC2_HOST, PAG_EC2_PATH, PAG_EC2_KEY are all set"
  if [ ! -f "$PAG_EC2_KEY" ]; then
    gate_fail "SSH key not found at PAG_EC2_KEY='$PAG_EC2_KEY'" \
              "point PAG_EC2_KEY at the deploy key file"
  else
    KEY_PERMS="$(stat -f '%Lp' "$PAG_EC2_KEY" 2>/dev/null || stat -c '%a' "$PAG_EC2_KEY")"
    if [ "$KEY_PERMS" = "600" ] || [ "$KEY_PERMS" = "400" ]; then
      pass "SSH key permissions are $KEY_PERMS"
    else
      gate_fail "SSH key '$PAG_EC2_KEY' has permissions $KEY_PERMS; SSH requires 600 or 400" \
                "chmod 600 '$PAG_EC2_KEY'"
    fi
  fi
fi

# Appcast <-> DMG consistency: the newest item's DMG must exist locally and
# its real version/length must match what the appcast advertises (#0041).
NEWEST_ENCLOSURE_URL="$(sed -nE 's/.*url="([^"]+\.dmg)".*/\1/p' "$APPCAST" | head -1)"
if [ -z "$NEWEST_ENCLOSURE_URL" ]; then
  pass "appcast has no items yet — nothing to cross-check against downloads (note: first release)"
else
  DMG_NAME="$(basename "$NEWEST_ENCLOSURE_URL")"
  DMG_FILE="$DOWNLOADS_DIR/$DMG_NAME"
  APPCAST_LENGTH="$(sed -nE 's/.*length="([0-9]+)".*/\1/p' "$APPCAST" | head -1)"
  APPCAST_SHORT_VERSION="$NEWEST_APPCAST_VERSION"
  if [ ! -f "$DMG_FILE" ]; then
    gate_fail "newest appcast item references $DMG_NAME but it is not in website/downloads/" \
              "copy the released DMG into website/downloads/ (see scripts/release.sh output)"
  else
    REAL_LENGTH="$(stat -f%z "$DMG_FILE")"
    if [ "$REAL_LENGTH" != "$APPCAST_LENGTH" ]; then
      gate_fail "appcast advertises length=$APPCAST_LENGTH but $DMG_NAME is $REAL_LENGTH bytes" \
                "regenerate the item from the real artifact: scripts/appcast-item.sh website/downloads/$DMG_NAME"
    else
      pass "appcast enclosure length matches $DMG_NAME ($REAL_LENGTH bytes)"
    fi
    # Mount read-only and compare the real app version (same approach as appcast-item.sh).
    MOUNT_POINT="$(mktemp -d "${TMPDIR:-/tmp}/preflight-dmg.XXXXXX")"
    if hdiutil attach -readonly -nobrowse -mountpoint "$MOUNT_POINT" "$DMG_FILE" -quiet; then
      DMG_APP="$(find "$MOUNT_POINT" -maxdepth 1 -name '*.app' -print -quit)"
      DMG_VERSION=""
      [ -n "$DMG_APP" ] && DMG_VERSION="$(plutil -extract CFBundleShortVersionString raw -o - "$DMG_APP/Contents/Info.plist" 2>/dev/null || true)"
      hdiutil detach "$MOUNT_POINT" -quiet 2>/dev/null || true
      rmdir "$MOUNT_POINT" 2>/dev/null || true
      if [ -z "$DMG_VERSION" ]; then
        gate_fail "could not read the app version from inside $DMG_NAME" \
                  "verify the DMG contains the app: scripts/verify-dmg.sh website/downloads/$DMG_NAME"
      elif [ "$DMG_VERSION" = "$APPCAST_SHORT_VERSION" ]; then
        pass "appcast shortVersionString $APPCAST_SHORT_VERSION matches the app inside $DMG_NAME"
      else
        gate_fail "appcast says $APPCAST_SHORT_VERSION but the app inside $DMG_NAME is $DMG_VERSION" \
                  "regenerate the item from the real artifact: scripts/appcast-item.sh website/downloads/$DMG_NAME"
      fi
    else
      rmdir "$MOUNT_POINT" 2>/dev/null || true
      gate_fail "hdiutil could not attach $DMG_FILE" \
                "verify the DMG: scripts/verify-dmg.sh website/downloads/$DMG_NAME"
    fi
  fi
fi

# ===========================================================================
section "Hygiene gates"
# ===========================================================================

DIRTY="$(git -C "$REPO_ROOT" status --porcelain)"
if [ -z "$DIRTY" ]; then
  pass "working tree is clean"
elif [ "$ALLOW_DIRTY" -eq 1 ]; then
  warn "working tree is dirty ($(echo "$DIRTY" | wc -l | tr -d ' ') entries) — allowed by --allow-dirty" \
       "commit or stash before the real release"
else
  gate_fail "working tree is dirty — releases must come from a committed state" \
            "commit or stash changes (git status), or re-run with --allow-dirty for a dry run"
fi

# ===========================================================================
section "Summary"
# ===========================================================================

echo "passed: $PASS_COUNT   failed: $FAIL_COUNT   warnings: $WARN_COUNT   skipped: $SKIP_COUNT"
if [ "$FAIL_COUNT" -gt 0 ]; then
  echo "NOT READY: $FAIL_COUNT gate(s) failed. Fix the [✗] items above before scripts/release.sh."
  exit 1
fi
if [ "$WARN_COUNT" -gt 0 ]; then
  echo "READY (with $WARN_COUNT warning(s) — re-run with --strict to treat them as failures)."
else
  echo "READY: all gates passed."
fi
exit 0
