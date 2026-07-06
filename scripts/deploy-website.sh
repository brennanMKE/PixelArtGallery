#!/usr/bin/env bash
#
# deploy-website.sh — push website/ to the public host via rsync over SSH.
#
# Required environment variables:
#   PAG_EC2_HOST  Deploy target as user@host (e.g. ubuntu@pixelartgallery.sstools.co)
#   PAG_EC2_PATH  Absolute document-root path on the host (e.g. /var/www/pixelartgallery)
#   PAG_EC2_KEY   Path to the SSH private key (must exist, permissions 600 or 400)
# Optional:
#   PAG_EC2_PORT  SSH port (default: 22)
#
# Usage:
#   scripts/deploy-website.sh          # dry-run preview, then confirm prompt
#   scripts/deploy-website.sh --yes    # skip the confirm prompt
#
# Notes:
#   - Deletes remote files that no longer exist locally, EXCEPT anything under
#     downloads/ — DMGs uploaded by the release flow are never deleted just
#     because the local downloads/ folder is empty.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WEBSITE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)/website"

ASSUME_YES=0
for arg in "$@"; do
    case "${arg}" in
        --yes|-y) ASSUME_YES=1 ;;
        --help|-h)
            sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            echo "error: unknown argument '${arg}' (supported: --yes, --help)" >&2
            exit 2
            ;;
    esac
done

fail=0

# --- Validate environment -----------------------------------------------------

if [[ -z "${PAG_EC2_HOST:-}" ]]; then
    echo "error: PAG_EC2_HOST is not set. Set it to the deploy target, e.g." >&2
    echo "       export PAG_EC2_HOST='ubuntu@pixelartgallery.sstools.co'" >&2
    fail=1
fi

if [[ -z "${PAG_EC2_PATH:-}" ]]; then
    echo "error: PAG_EC2_PATH is not set. Set it to the remote document root, e.g." >&2
    echo "       export PAG_EC2_PATH='/var/www/pixelartgallery'" >&2
    fail=1
fi

if [[ -z "${PAG_EC2_KEY:-}" ]]; then
    echo "error: PAG_EC2_KEY is not set. Set it to your SSH private key path, e.g." >&2
    echo "       export PAG_EC2_KEY=\"\$HOME/.ssh/pag-deploy.pem\"" >&2
    fail=1
fi

if [[ ${fail} -ne 0 ]]; then
    echo >&2
    echo "Nothing was deployed. Set the variables above and re-run." >&2
    exit 1
fi

PORT="${PAG_EC2_PORT:-22}"

if [[ ! "${PORT}" =~ ^[0-9]+$ ]]; then
    echo "error: PAG_EC2_PORT must be a number (got '${PORT}')." >&2
    exit 1
fi

if [[ ! -f "${PAG_EC2_KEY}" ]]; then
    echo "error: SSH key not found at PAG_EC2_KEY='${PAG_EC2_KEY}'." >&2
    exit 1
fi

key_perms="$(stat -f '%Lp' "${PAG_EC2_KEY}" 2>/dev/null || stat -c '%a' "${PAG_EC2_KEY}")"
if [[ "${key_perms}" != "600" && "${key_perms}" != "400" ]]; then
    echo "error: SSH key '${PAG_EC2_KEY}' has permissions ${key_perms}; SSH requires 600 or 400." >&2
    echo "       Fix with: chmod 600 '${PAG_EC2_KEY}'" >&2
    exit 1
fi

if [[ ! -d "${WEBSITE_DIR}" || ! -f "${WEBSITE_DIR}/index.html" ]]; then
    echo "error: website directory not found or missing index.html at '${WEBSITE_DIR}'." >&2
    exit 1
fi

# --- Preview (dry run) ---------------------------------------------------------

RSYNC_ARGS=(
    --archive
    --compress
    --verbose
    --human-readable
    --delete
    --filter='P downloads/*'
    -e "ssh -i ${PAG_EC2_KEY} -p ${PORT}"
    "${WEBSITE_DIR}/"
    "${PAG_EC2_HOST}:${PAG_EC2_PATH}/"
)

echo "Deploying: ${WEBSITE_DIR}/"
echo "       To: ${PAG_EC2_HOST}:${PAG_EC2_PATH}/ (port ${PORT})"
echo
echo "--- Dry run (no changes made) ---"
rsync --dry-run "${RSYNC_ARGS[@]}"
echo "--- End dry run ---"
echo

# --- Confirm and deploy --------------------------------------------------------

if [[ ${ASSUME_YES} -ne 1 ]]; then
    read -r -p "Proceed with deploy? [y/N] " answer
    case "${answer}" in
        y|Y|yes|YES) ;;
        *)
            echo "Aborted. Nothing was deployed."
            exit 0
            ;;
    esac
fi

rsync "${RSYNC_ARGS[@]}"
echo
echo "Deploy complete: https://pixelartgallery.sstools.co/"
