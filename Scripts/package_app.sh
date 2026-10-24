#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-release}"
APP_DIR="$ROOT/build/ClipGum.app"

cd "$ROOT"
swift build --configuration "$CONFIGURATION" --product ClipGum
BIN_DIR="$(swift build --configuration "$CONFIGURATION" --show-bin-path)"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN_DIR/ClipGum" "$APP_DIR/Contents/MacOS/ClipGum"
cp "$ROOT/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
printf 'APPL????' > "$APP_DIR/Contents/PkgInfo"
chmod +x "$APP_DIR/Contents/MacOS/ClipGum"

plutil -lint "$APP_DIR/Contents/Info.plist"
codesign --force --sign - \
  --entitlements "$ROOT/Resources/ClipGum.entitlements" \
  "$APP_DIR"
codesign --verify --verbose=2 "$APP_DIR"

printf '\nBuilt %s\n' "$APP_DIR"
if [[ "${1:-}" == "--open" ]]; then
  open "$APP_DIR"
fi
