#!/usr/bin/env bash
set -euo pipefail
trap 'status=$?; printf "::error::Development packaging failed near line %s (exit %s).\n" "$LINENO" "$status" >&2' ERR

VERSION="${1:?usage: Build/package_development.sh VERSION BUILD_NUMBER HTTPS_DMG_URL [output-directory]}"
BUILD_NUMBER="${2:?numeric build number required}"
DOWNLOAD_URL="${3:?HTTPS DMG download URL required}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="${4:-$ROOT/build/distribution}"
DMG_NAME="ClipGum-$VERSION.dmg"
DMG_PATH="$OUTPUT_DIR/$DMG_NAME"
CASK_PATH="$OUTPUT_DIR/clipgum.rb"

[[ "$VERSION" =~ ^[0-9A-Za-z.-]+$ ]] || { echo "Unsafe development version" >&2; exit 2; }
[[ "$BUILD_NUMBER" =~ ^[0-9]+$ ]] || { echo "Development build number must be numeric" >&2; exit 2; }
[[ "$DOWNLOAD_URL" == https://* ]] || { echo "Development DMG URL must use HTTPS" >&2; exit 2; }

cd "$ROOT"
VERSION="$VERSION" BUILD_NUMBER="$BUILD_NUMBER" SIGNING_IDENTITY="-" \
  ./Scripts/package_app.sh
./Build/validate_distribution.sh "$ROOT/build/ClipGum.app" --development
./Build/create_dmg.sh "$ROOT/build/ClipGum.app" "$DMG_PATH"
./Build/generate_cask.sh "$DMG_PATH" "$VERSION" "$DOWNLOAD_URL" "$CASK_PATH"

# A development cask must disclose its Gatekeeper boundary before installation.
python3 - "$CASK_PATH" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
ending = "\nend\n"
if not text.endswith(ending):
    raise SystemExit("Unexpected generated cask structure")
caveats = '''
  caveats do
    "Development build only: ad-hoc signed and not notarized. macOS may require explicit Open Anyway approval in System Settings > Privacy & Security."
  end
'''
path.write_text(text[:-len(ending)] + caveats + "end\n")
PY
ruby -c "$CASK_PATH"

MOUNT_POINT="$(mktemp -d -t clipgum-development-dmg)"
MOUNTED=0
cleanup() {
  local status=$?
  trap - EXIT
  if [[ "$MOUNTED" == "1" ]]; then
    hdiutil detach "$MOUNT_POINT" >/dev/null 2>&1 || true
  fi
  rm -rf "$MOUNT_POINT"
  exit "$status"
}
trap cleanup EXIT

hdiutil attach "$DMG_PATH" -nobrowse -readonly -mountpoint "$MOUNT_POINT"
MOUNTED=1
[[ -d "$MOUNT_POINT/ClipGum.app" ]]
[[ -L "$MOUNT_POINT/Applications" ]]
./Build/validate_distribution.sh "$MOUNT_POINT/ClipGum.app" --development
hdiutil detach "$MOUNT_POINT"
MOUNTED=0
rm -rf "$MOUNT_POINT"

(
  cd "$OUTPUT_DIR"
  shasum -a 256 "$DMG_NAME" > SHA256SUMS.txt
)

COMMIT="${GITHUB_SHA:-$(git rev-parse HEAD)}"
RUN_URL="${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY:-Bwillou1/ClipGum}/actions/runs/${GITHUB_RUN_ID:-local}"
CASK_URL="${DOWNLOAD_URL%/*}/clipgum.rb"
cat > "$OUTPUT_DIR/RELEASE_NOTES.md" <<NOTES
# ClipGum $VERSION — development prerelease

Built from commit \`$COMMIT\`. The full CI test suite passed before publication.
CI run: $RUN_URL

## Requirements

- Apple Silicon Mac (arm64)
- macOS 14 Sonoma or newer

## Install with Homebrew

\`\`\`bash
curl -fLO "$CASK_URL"
brew install --cask ./clipgum.rb
\`\`\`

## Install directly

Download and open [$DMG_NAME]($DOWNLOAD_URL), then drag **ClipGum.app** to **Applications**.

## Development-build warning

This build is **ad-hoc signed and not notarized**. It is intended for testing, not production distribution. macOS may require an explicit **Open Anyway** approval in **System Settings → Privacy & Security**. Only bypass that warning if you trust this CI artifact.

The Sparkle update feed is not configured in this development build. Verify the DMG against \`SHA256SUMS.txt\` before installation.
NOTES

printf 'Development package ready: %s\n' "$DMG_PATH"
printf 'Homebrew cask ready: %s\n' "$CASK_PATH"
