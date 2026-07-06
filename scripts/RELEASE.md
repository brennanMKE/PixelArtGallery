# Releasing Pixel Art Gallery (macOS)

The end-to-end checklist for cutting a signed, notarized, direct-download
release. Every step is scripted; this document is the order to run them in
and what to check between steps. The Sparkle key/appcast details live in
[`scripts/SPARKLE.md`](SPARKLE.md); the v1.0.0 go/no-go gate lives in
[`Ship-v1.md`](../Ship-v1.md) at the repo root.

> **User-run steps.** Notarization submissions (`scripts/release.sh` without
> `--dry-run`, i.e. `xcrun notarytool submit`) and website deploys
> (`scripts/deploy-website.sh`) contact Apple / the production host. These are
> **user-run** steps — agents must not submit builds to Apple or deploy the
> website autonomously.

## One-time setup (per machine)

### 1. Developer ID Application certificate

Releases are signed with a `Developer ID Application` certificate for team
`XV8BAAVZ6V`. Install it via Xcode → Settings → Accounts → Manage
Certificates, or create/download one at
<https://developer.apple.com/account/resources/certificates>. Verify:

```sh
security find-identity -v -p codesigning | grep "Developer ID Application"
```

Both `scripts/release.sh` and `scripts/preflight.sh` fail early if it is
missing.

### 2. Notary keychain profile

```sh
scripts/setup-keys.sh
```

Interactive, one time only. It runs
`xcrun notarytool store-credentials PixelArtGallery-notary --team-id XV8BAAVZ6V`,
prompting for the Apple ID, the team ID, and an **app-specific password**
(created at <https://account.apple.com> → App-Specific Passwords — never your
Apple ID password). Credentials live only in the keychain under the profile
name `PixelArtGallery-notary`; nothing is committed. The script verifies the
profile with a `notarytool history` probe before declaring success.

### 3. Sparkle EdDSA signing key

The key pair **already exists on this Mac** — it was generated for #0039 and
lives in the login keychain under account `PixelArtGallery`. Do **not**
generate a new one here: a new key would not match the `SUPublicEDKey` baked
into shipped apps, and installed copies could never verify another update.

What you actually need to do on this machine is **back it up** (once):

```sh
# generate_keys lives in the Sparkle SPM artifacts — see SPARKLE.md for paths
generate_keys -x /path/to/offline-backup/pixelartgallery-eddsa.key --account PixelArtGallery
```

Store the exported file offline (not in the repo, not in cloud-synced
folders). On a **new machine**, restore from that backup instead of
generating:

```sh
generate_keys -f /path/to/offline-backup/pixelartgallery-eddsa.key --account PixelArtGallery
```

Only if starting a brand-new product line (never for this app while users
have installed builds) would you run plain
`generate_keys --account PixelArtGallery`. Full details, tool locations, and
the `sign_update` conventions: [`SPARKLE.md`](SPARKLE.md).

### 4. Website deploy environment variables

`scripts/deploy-website.sh` and the preflight website gates need:

```sh
export PAG_EC2_HOST='ubuntu@pixelartgallery.sstools.co'  # user@host
export PAG_EC2_PATH='/var/www/pixelartgallery'           # remote document root
export PAG_EC2_KEY="$HOME/.ssh/pag-deploy.pem"           # SSH key, chmod 600
export PAG_EC2_PORT=22                                    # optional, default 22
```

The key file must exist with `600` or `400` permissions or the scripts refuse
to run.

## Per-release sequence

1. **Preflight.**

   ```sh
   scripts/preflight.sh
   ```

   Runs every gate (builds + tests, versioning, Sparkle wiring, sandbox off /
   hardened runtime on, signing cert + notary profile, deploy env vars,
   appcast↔DMG consistency, clean tree) with `[✓]`/`[✗]`/`[!]`/`[-]` output.
   Fix every `[✗]` before continuing. Flags: `--skip-build` (fast re-run,
   probes the last `build/preflight` products), `--strict` (warnings fail),
   `--allow-dirty` (dry runs only).

2. **Bump the version.** Edit the single source of truth,
   `Configuration/Build.xcconfig`:

   ```
   MARKETING_VERSION = <X.Y.Z>
   ```

   Commit exactly as `Bump version to <X.Y.Z>` (SemVer, three parts —
   the changelog anchors are `#vX-Y-Z`). **Never** bump via Xcode's target
   editor: it writes `MARKETING_VERSION` back into `project.pbxproj`, which
   silently overrides the xcconfig; preflight's version gate catches this.
   You do not touch the build number — `release.sh` injects
   `CURRENT_PROJECT_VERSION=$(date -u +%Y%m%d)` (UTC date) at archive time,
   which is the value Sparkle compares.

3. **Tests and builds.** (Preflight already ran these; re-run directly if
   anything changed since.)

   ```sh
   cd PixelArtGalleryKit && swift test    # expect 92 tests, 0 failures
   xcodebuild -project PixelArtGallery.xcodeproj -scheme PixelArtGallery -destination 'platform=macOS' build
   xcodebuild -project PixelArtGallery.xcodeproj -scheme PixelArtGallery -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
   ```

4. **Release build** *(user-run — submits to Apple)*:

   ```sh
   scripts/release.sh
   ```

   Pipeline: preflight → archive (Release, `generic/platform=macOS`) →
   Developer ID export → codesign verify → notarize app (`notarytool submit
   --wait`) → staple app → DMG at `dist/PixelArtGallery-<X.Y.Z>.dmg` →
   sign DMG → notarize DMG (a second, fast pass — a DMG can only be stapled
   if the DMG itself is notarized) → staple DMG → `verify-dmg.sh` → prints
   the ready-to-paste appcast `<item>`. `--dry-run` (alias
   `--skip-notarize`) stops after export + codesign verification and never
   contacts Apple.

5. **Verify the DMG** (release.sh already ran this as its last step; run it
   independently any time):

   ```sh
   scripts/verify-dmg.sh dist/PixelArtGallery-<X.Y.Z>.dmg
   ```

   Six checks: DMG spctl assessment, DMG staple, app deep codesign, app
   Developer ID authority, app staple, and Gatekeeper `spctl --assess --type
   execute` on a copy carrying a **fresh** quarantine xattr. All must PASS.

6. **Clean-Mac smoke test.** On a Mac that has never seen the app, download
   the DMG **via a browser** (so it carries the quarantine attribute), mount,
   drag to /Applications, launch. No "unidentified developer" or "damaged"
   dialog may appear. This is the only real proof of Gatekeeper acceptance.

7. **Appcast item.** `release.sh` printed the `<item>` block (or regenerate
   with `scripts/appcast-item.sh dist/PixelArtGallery-<X.Y.Z>.dmg` — never
   hand-type one; every attribute is derived from the artifact). Paste it
   into `website/appcast.xml` **above** any existing items (newest first,
   inside `<channel>`), then write the release notes into the item's
   `<description><![CDATA[ … ]]></description>` placeholder (HTML allowed —
   this is what Sparkle shows users in the update window).

8. **Stage the DMG for download:**

   ```sh
   cp dist/PixelArtGallery-<X.Y.Z>.dmg website/downloads/
   ```

9. **Re-run preflight.** The website gate mounts the newest appcast item's
   DMG from `website/downloads/` and cross-checks the advertised
   version/length against the real artifact — this is the appcast↔DMG
   consistency gate. It must be green before deploying.

   ```sh
   scripts/preflight.sh --skip-build
   ```

10. **Deploy the website** *(user-run)*:

    ```sh
    scripts/deploy-website.sh
    ```

    Validates env vars and key permissions, shows an rsync `--dry-run`
    preview, asks for confirmation (`--yes` to skip), then pushes `website/`.
    Remote `downloads/` files are protected from deletion
    (`--filter='P downloads/*'`).

11. **Tag:**

    ```sh
    git tag v<X.Y.Z>
    ```

    (`release.sh`'s next-steps hint suggests a `v<X.Y.Z>-<build>` form; the
    repo convention is the plain SemVer tag — the build number is recoverable
    from the appcast's `sparkle:version`.)

12. **Mirror the release notes** in `website/changelog.html`: add an
    `<article id="vX-Y-Z">` (newest first) with the same notes — the appcast
    item's `<link>` points at `changelog.html#vX-Y-Z`. Redeploy if you edited
    it after step 10.

## Troubleshooting

- **`notarytool` says Invalid / rejected.** Get the full report:

  ```sh
  xcrun notarytool log <submission-id> --keychain-profile PixelArtGallery-notary
  ```

  The submission ID is printed by `notarytool submit`. Typical causes:
  hardened runtime off, unsigned nested code, or a certificate/team mismatch.

- **`notary keychain profile 'PixelArtGallery-notary' is missing`.** Run
  `scripts/setup-keys.sh` once. If it fails to authenticate, the password
  was probably the Apple ID password instead of an app-specific one.

- **Stapling the DMG fails with Error 65 / "not eligible".** The DMG itself
  must be notarized before it can be stapled — stapling the app inside is not
  enough. `release.sh` handles this with a second (fast) `notarytool submit`
  for the DMG; if you built a DMG by hand, submit the DMG too.

- **`sign_update` / `appcast-item.sh` appears to hang.** The first
  `sign_update` run from a given binary path pops a macOS keychain
  authorization dialog (the EdDSA key's ACL is per-binary). Click "Always
  Allow" — once per binary path (the package `.build` copy and the
  DerivedData copy are separate binaries).

- **A script's `grep -q` pipeline "fails" even though the text matched.**
  These scripts run under `set -o pipefail`; `grep -q` exits at the first
  match, the upstream command (e.g. `codesign`) takes a SIGPIPE, and the
  pipeline reports failure. Capture output into a variable first, then grep
  the variable — the existing scripts already do this; keep the pattern when
  editing them.

- **Version bump doesn't take effect.** Xcode's target editor wrote
  `MARKETING_VERSION` back into `project.pbxproj`, and target-level pbxproj
  settings silently beat the xcconfig. Delete the pbxproj line; bump only in
  `Configuration/Build.xcconfig`. `scripts/preflight.sh` fails the release
  when a `MARKETING_VERSION` line reappears in the pbxproj.

- **`spctl` verdicts look stale or too lenient.** Gatekeeper only assesses
  quarantined files, and prior approvals are cached — re-assessing a copy
  you already opened proves nothing about a fresh download. That is why
  `verify-dmg.sh` writes a fresh `com.apple.quarantine` xattr onto a pristine
  copy before its `spctl --assess --type execute` check, and why the
  clean-Mac smoke test must download via a browser.
