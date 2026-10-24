#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
: "${VERSION:?Set VERSION}"
: "${BUILD_NUMBER:?Set BUILD_NUMBER}"
: "${SIGNING_IDENTITY:?Set a Developer ID Application signing identity}"
: "${NOTARYTOOL_PROFILE:?Set a notarytool Keychain profile}"
: "${CLIPGUM_APPCAST_URL:?Set the production HTTPS appcast URL}"
: "${CLIPGUM_SPARKLE_PUBLIC_ED_KEY:?Set the Sparkle Ed25519 public key}"
: "${CLIPGUM_DMG_DOWNLOAD_URL:?Set the final HTTPS DMG URL}"
[[ "$SIGNING_IDENTITY" != "-" ]] || { echo "Distribution cannot use ad-hoc signing" >&2; exit 2; }

OUT="$ROOT/build/distribution"
APP="$OUT/ClipGum.app"
DMG="$OUT/ClipGum-$VERSION.dmg"
mkdir -p "$OUT"
cd "$ROOT"
swift package resolve
python3 Build/generate_sbom.py --sync-resource

export VERSION BUILD_NUMBER SIGNING_IDENTITY CLIPGUM_APPCAST_URL CLIPGUM_SPARKLE_PUBLIC_ED_KEY
export APP_DIR="$APP" REQUIRE_UPDATE_CONFIGURATION=1 CONFIGURATION=release
./Scripts/package_app.sh
./Build/validate_distribution.sh "$APP" --production
./Build/create_dmg.sh "$APP" "$DMG" "$SIGNING_IDENTITY"
./Build/notarize.sh "$DMG" "$NOTARYTOOL_PROFILE"
./Build/generate_cask.sh "$DMG" "$VERSION" "$CLIPGUM_DMG_DOWNLOAD_URL" "$OUT/clipgum.rb"
python3 Build/generate_sbom.py --output "$OUT/SBOM.json"
./Build/generate_appcast.sh \
  "$DMG" "$VERSION" "$BUILD_NUMBER" "${RELEASE_CHANNEL:-stable}" \
  "$CLIPGUM_DMG_DOWNLOAD_URL" "$OUT/appcast.xml"

printf '\nDistribution artifacts in %s\n' "$OUT"
printf 'Upload the DMG, publish appcast.xml at CLIPGUM_APPCAST_URL, and submit clipgum.rb to the intended Homebrew tap.\n'
