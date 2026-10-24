#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-release}"
APP_DIR="${APP_DIR:-$ROOT/build/ClipGum.app}"
cd "$ROOT"

swift build --configuration "$CONFIGURATION" --product ClipGum
BIN_DIR="$(swift build --configuration "$CONFIGURATION" --show-bin-path)"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources" "$APP_DIR/Contents/Frameworks"
cp "$BIN_DIR/ClipGum" "$APP_DIR/Contents/MacOS/ClipGum"
cp "$ROOT/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"

if [[ -n "${VERSION:-}" ]]; then
  plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP_DIR/Contents/Info.plist"
fi
if [[ -n "${BUILD_NUMBER:-}" ]]; then
  plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$APP_DIR/Contents/Info.plist"
fi

FEED_URL="${CLIPGUM_APPCAST_URL:-}"
PUBLIC_ED_KEY="${CLIPGUM_SPARKLE_PUBLIC_ED_KEY:-}"
if [[ "${REQUIRE_UPDATE_CONFIGURATION:-0}" == "1" && ( -z "$FEED_URL" || -z "$PUBLIC_ED_KEY" ) ]]; then
  echo "Release packaging requires CLIPGUM_APPCAST_URL and CLIPGUM_SPARKLE_PUBLIC_ED_KEY" >&2
  exit 2
fi
if [[ -n "$FEED_URL" || -n "$PUBLIC_ED_KEY" ]]; then
  [[ -n "$FEED_URL" && -n "$PUBLIC_ED_KEY" ]] || { echo "Update feed and public key must be supplied together" >&2; exit 2; }
  [[ "$FEED_URL" == https://* ]] || { echo "The appcast must use strict HTTPS" >&2; exit 2; }
  plutil -replace SUFeedURL -string "$FEED_URL" "$APP_DIR/Contents/Info.plist"
  plutil -replace SUPublicEDKey -string "$PUBLIC_ED_KEY" "$APP_DIR/Contents/Info.plist"
fi

# Preserve every generated dependency resource bundle and MLX Metal library.
shopt -s nullglob
for bundle in "$BIN_DIR"/*.bundle; do
  cp -R "$bundle" "$APP_DIR/Contents/Resources/"
done
for metallib in "$BIN_DIR"/*.metallib; do
  cp "$metallib" "$APP_DIR/Contents/MacOS/"
done
shopt -u nullglob

# SwiftPM command-line executables do not perform Xcode's Embed Frameworks
# phase. Locate Sparkle's pinned Apple Silicon binary slice explicitly.
SPARKLE_FRAMEWORK="${SPARKLE_FRAMEWORK:-}"
if [[ -z "$SPARKLE_FRAMEWORK" ]]; then
  while IFS= read -r candidate; do
    case "$candidate" in
      *Sparkle.xcframework/macos-arm64/*) SPARKLE_FRAMEWORK="$candidate"; break ;;
    esac
    [[ -n "$SPARKLE_FRAMEWORK" ]] || SPARKLE_FRAMEWORK="$candidate"
  done < <(find "$ROOT/.build/artifacts" -type d -name 'Sparkle.framework' -print 2>/dev/null | sort)
fi
[[ -d "$SPARKLE_FRAMEWORK" ]] || { echo "Unable to locate Sparkle.framework; run swift package resolve" >&2; exit 1; }
ditto "$SPARKLE_FRAMEWORK" "$APP_DIR/Contents/Frameworks/Sparkle.framework"

RPATH_REPORT="$(otool -l "$APP_DIR/Contents/MacOS/ClipGum")"
if [[ "$RPATH_REPORT" != *'@executable_path/../Frameworks'* ]]; then
  install_name_tool -add_rpath '@executable_path/../Frameworks' "$APP_DIR/Contents/MacOS/ClipGum"
fi
cp "$ROOT/Build/SBOM.json" "$APP_DIR/Contents/Resources/SBOM.json"
printf 'APPL????' > "$APP_DIR/Contents/PkgInfo"
chmod +x "$APP_DIR/Contents/MacOS/ClipGum"
plutil -lint "$APP_DIR/Contents/Info.plist"

"$ROOT/Build/sign_app.sh" "$APP_DIR" "${SIGNING_IDENTITY:--}"
printf '\nBuilt %s\n' "$APP_DIR"
if [[ "${1:-}" == "--open" ]]; then
  open "$APP_DIR"
fi
