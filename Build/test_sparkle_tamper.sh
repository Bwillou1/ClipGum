#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SIGN_UPDATE="${SPARKLE_SIGN_UPDATE:-}"
if [[ -z "$SIGN_UPDATE" ]]; then
  while IFS= read -r candidate; do SIGN_UPDATE="$candidate"; break; done < <(
    find "$ROOT/.build/artifacts" -type f -path '*/Sparkle/bin/sign_update' -print 2>/dev/null | sort
  )
fi
if [[ ! -x "$SIGN_UPDATE" ]]; then
  printf '::error::Sparkle 2.10.0 sign_update was not found or is not executable (path=%s).\n' "$SIGN_UPDATE"
  exit 2
fi
printf 'Using Sparkle sign_update: %s\n' "$SIGN_UPDATE"
file "$SIGN_UPDATE"

TEMP="$(mktemp -d -t clipgum-sparkle-tamper)"
trap 'rm -rf "$TEMP"' EXIT
KEY="$TEMP/test-only-ed25519.key"
ARCHIVE="$TEMP/ClipGum-test-update.dmg"
TAMPERED="$TEMP/ClipGum-tampered-update.dmg"
# Deterministic, public, test-only seed. This is never a production credential.
printf '%s' 'ClipGum Sparkle tamper integration test; never use for a release' \
  | openssl dgst -sha256 -binary | base64 >"$KEY"
chmod 600 "$KEY"
printf 'ClipGum signed-update integration fixture\n' >"$ARCHIVE"
cp "$ARCHIVE" "$TAMPERED"

if ! SIGNATURE="$("$SIGN_UPDATE" --ed-key-file "$KEY" -p "$ARCHIVE" 2>&1)"; then
  printf '::error::Sparkle could not sign the intact fixture with the supported 32-byte test seed. Output: %s\n' "$SIGNATURE"
  exit 11
fi
if [[ ! "$SIGNATURE" =~ ^[A-Za-z0-9+/]+={0,2}$ ]]; then
  printf '::error::Sparkle returned malformed signature metadata for the intact fixture.\n'
  exit 12
fi
if ! "$SIGN_UPDATE" --ed-key-file "$KEY" --verify "$ARCHIVE" "$SIGNATURE"; then
  printf '::error::Sparkle rejected its own intact fixture signature.\n'
  exit 13
fi
printf 'X' | dd of="$TAMPERED" bs=1 seek=7 conv=notrunc 2>/dev/null
if "$SIGN_UPDATE" --ed-key-file "$KEY" --verify "$TAMPERED" "$SIGNATURE"; then
  printf '::error::Sparkle accepted a tampered update archive.\n'
  exit 14
fi
printf 'Sparkle rejected the tampered archive and accepted the intact fixture.\n'
