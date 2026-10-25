#!/usr/bin/env bash
set -euo pipefail

ARTIFACT="${1:?usage: Build/notarize.sh ClipGum.dmg [notarytool-keychain-profile]}"
PROFILE="${2:-${NOTARYTOOL_PROFILE:-${NOTARY_PROFILE:-}}}"
[[ -f "$ARTIFACT" ]] || { echo "Notarization artifact not found" >&2; exit 2; }
[[ -n "$PROFILE" ]] || { echo "Supply a notarytool Keychain profile name, never credentials in Git" >&2; exit 2; }

xcrun notarytool submit "$ARTIFACT" \
  --keychain-profile "$PROFILE" \
  --wait \
  --timeout 30m
xcrun stapler staple "$ARTIFACT"
xcrun stapler validate "$ARTIFACT"

case "$ARTIFACT" in
  *.dmg) spctl -a -t open --context context:primary -v "$ARTIFACT" ;;
  *.app) spctl -a -t execute -v "$ARTIFACT" ;;
esac
printf 'Notarized and stapled %s\n' "$ARTIFACT"
