# Pixel Art Gallery website

The public site for Pixel Art Gallery, served at `https://pixelartgallery.sstools.co`
(domain per #0039/#0040 — the app's `SUFeedURL` points at this host, so the
site must be served from that domain's root). Plain static HTML/CSS — no
framework, no build step. Open `index.html` directly from `file://` to preview.

## What's here

| Path | Purpose |
|---|---|
| `index.html` | Landing page: features, screenshots, download button, requirements |
| `changelog.html` | Versioned release notes; one `<article id="vX-Y-Z">` per release |
| `privacy.html` | Privacy policy |
| `appcast.xml` | Sparkle update feed the macOS app polls (`SUFeedURL`) |
| `css/site.css` | Single shared stylesheet (light/dark via `prefers-color-scheme`) |
| `assets/` | App icon renders, OpenGraph card, real app screenshots |
| `downloads/` | Versioned DMGs (`PixelArtGallery-<X.Y.Z>.dmg`) — see its README |

## How releases update this site

The release flow (see `scripts/release.sh` and issue #0041) does three things
per release; none of them are hand-edited:

1. Drops `PixelArtGallery-<X.Y.Z>.dmg` into `downloads/`.
2. Prepends a signed `<item>` to `appcast.xml` (newest first), whose release
   notes link points at `changelog.html#vX-Y-Z` and whose enclosure points at
   the DMG in `downloads/`.
3. A matching `<article id="vX-Y-Z">` entry is written in `changelog.html`
   (remove the "Upcoming" badge when the version actually ships).

The Download button in `index.html` points at the latest versioned DMG —
update its `href` when a new version ships.

## Deploying

```sh
export PAG_EC2_HOST='user@host'            # deploy target
export PAG_EC2_PATH='/var/www/pixelartgallery'  # remote document root
export PAG_EC2_KEY="$HOME/.ssh/your-key.pem"    # SSH key (chmod 600)
export PAG_EC2_PORT=22                     # optional, default 22

scripts/deploy-website.sh        # dry-run preview + confirm prompt
scripts/deploy-website.sh --yes  # skip the prompt
```

The script validates the environment and key permissions, previews with
`rsync --dry-run`, then syncs `website/` to the host. Remote files deleted
locally are removed, except anything under `downloads/` (release DMGs on the
server are never deleted by a website deploy).
