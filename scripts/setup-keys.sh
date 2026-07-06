#!/bin/bash
#
# setup-keys.sh — one-time notarization credential setup for PixelArtGallery.
#
# Stores an Apple notary service credential in the local keychain under the
# profile name "PixelArtGallery-notary" (used by scripts/release.sh).
# Nothing is written to the repository — secrets live only in your keychain.

set -euo pipefail

TEAM_ID="XV8BAAVZ6V"
NOTARY_PROFILE="PixelArtGallery-notary"

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

banner "Preflight"

command -v xcrun >/dev/null 2>&1 \
  || fail "xcrun not found." "Install Xcode command line tools: xcode-select --install"
xcrun --find notarytool >/dev/null 2>&1 \
  || fail "notarytool not found." "Requires Xcode 13+ (xcrun notarytool)."

banner "About this setup"

cat <<EOF
This stores notary credentials in your macOS keychain under the profile
name '$NOTARY_PROFILE'. You will be prompted for:

  1. Apple ID       — the developer account email for team $TEAM_ID
  2. Team ID        — enter: $TEAM_ID
  3. Password       — an APP-SPECIFIC password, NOT your Apple ID password.

To create an app-specific password:

  - Sign in at https://account.apple.com (Sign-In and Security section)
  - Choose "App-Specific Passwords" > "+" and name it e.g. "notarytool"
  - Copy the generated xxxx-xxxx-xxxx-xxxx value and paste it when prompted

The password is stored ONLY in your keychain. Never commit it, and never
put it in a file inside this repository.
EOF

banner "Storing credentials (interactive)"

xcrun notarytool store-credentials "$NOTARY_PROFILE" --team-id "$TEAM_ID" \
  || fail "store-credentials failed." \
          "Check the Apple ID, team ID ($TEAM_ID), and that the password is an app-specific password."

banner "Verifying the stored profile"

xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" --output-format json >/dev/null \
  || fail "the stored profile did not authenticate against Apple's notary service." \
          "Re-run this script; make sure you used an app-specific password."

echo "Profile '$NOTARY_PROFILE' works. You can now run scripts/release.sh."
