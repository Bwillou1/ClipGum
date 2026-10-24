#!/usr/bin/env bash
set -euo pipefail

APP_BUNDLE="${1:?usage: Build/create_dmg.sh ClipGum.app ClipGum-version.dmg [identity]}"
DMG_PATH="${2:?output DMG path required}"
IDENTITY="${3:-}"
[[ -d "$APP_BUNDLE/Contents" ]] || { echo "App bundle not found" >&2; exit 2; }
mkdir -p "$(dirname "$DMG_PATH")"
STAGING="$(mktemp -d -t clipgum-dmg)"
trap 'rm -rf "$STAGING"' EXIT

ditto "$APP_BUNDLE" "$STAGING/ClipGum.app"
ln -s /Applications "$STAGING/Applications"
rm -f "$DMG_PATH"
hdiutil create \
  -volname ClipGum \
  -srcfolder "$STAGING" \
  -ov \
  -format UDZO \
  -imagekey zlib-level=9 \
  "$DMG_PATH"

if [[ -n "$IDENTITY" ]]; then
  codesign --force --sign "$IDENTITY" --timestamp "$DMG_PATH"
  codesign --verify --verbose=2 "$DMG_PATH"
fi
hdiutil verify "$DMG_PATH"
printf 'Created %s\n' "$DMG_PATH"
