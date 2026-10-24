#!/usr/bin/env bash
set -euo pipefail

APP_BUNDLE="${1:?usage: Build/sign_app.sh /path/ClipGum.app [signing-identity]}"
IDENTITY="${2:-${SIGNING_IDENTITY:--}}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENTITLEMENTS="${ENTITLEMENTS:-$ROOT/Resources/ClipGum.entitlements}"

[[ -d "$APP_BUNDLE/Contents" ]] || { echo "Not an app bundle: $APP_BUNDLE" >&2; exit 2; }

COMMON=(--force --sign "$IDENTITY" --options runtime)
if [[ "$IDENTITY" != "-" ]]; then
  COMMON+=(--timestamp)
fi

sign_nested() {
  local item="$1"
  local entitlement_file
  entitlement_file="$(mktemp -t clipgum-entitlements)"
  local entitlement_args=()
  # Preserve Sparkle helper/XPC sandbox entitlements, never the main app's
  # network-client entitlement. Unsigned nested code receives no entitlements.
  if codesign -d --entitlements :- "$item" >"$entitlement_file" 2>/dev/null \
    && grep -q '<key>' "$entitlement_file"; then
    entitlement_args=(--entitlements "$entitlement_file")
  fi
  codesign "${COMMON[@]}" "${entitlement_args[@]}" "$item"
  rm -f "$entitlement_file"
}

if [[ -d "$APP_BUNDLE/Contents/Frameworks" ]]; then
  while IFS= read -r -d '' item; do sign_nested "$item"; done < <(
    find "$APP_BUNDLE/Contents/Frameworks" -type f \( -name '*.dylib' -o -name 'Autoupdate' -o -name 'Updater' \) -print0
  )
  while IFS= read -r -d '' item; do sign_nested "$item"; done < <(
    find "$APP_BUNDLE/Contents/Frameworks" -depth -type d -name '*.xpc' -print0
  )
  while IFS= read -r -d '' item; do sign_nested "$item"; done < <(
    find "$APP_BUNDLE/Contents/Frameworks" -depth -type d -name '*.app' -print0
  )
  while IFS= read -r -d '' item; do sign_nested "$item"; done < <(
    find "$APP_BUNDLE/Contents/Frameworks" -depth -type d -name '*.framework' -print0
  )
fi

codesign "${COMMON[@]}" --entitlements "$ENTITLEMENTS" "$APP_BUNDLE"
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

# Fail if forbidden entitlements appear in the main executable.
SIGNED_ENTITLEMENTS="$(mktemp -t clipgum-signed-entitlements)"
codesign -d --entitlements :- "$APP_BUNDLE" >"$SIGNED_ENTITLEMENTS" 2>/dev/null
for forbidden in \
  com.apple.security.device.camera \
  com.apple.security.device.microphone \
  com.apple.security.personal-information.location \
  com.apple.security.cs.allow-jit \
  com.apple.security.cs.allow-unsigned-executable-memory \
  com.apple.security.cs.disable-library-validation; do
  if grep -q "$forbidden" "$SIGNED_ENTITLEMENTS"; then
    echo "Forbidden main-app entitlement: $forbidden" >&2
    rm -f "$SIGNED_ENTITLEMENTS"
    exit 1
  fi
done
rm -f "$SIGNED_ENTITLEMENTS"
printf 'Signed and verified %s\n' "$APP_BUNDLE"
