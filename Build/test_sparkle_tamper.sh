#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SIGN_UPDATE="${SPARKLE_SIGN_UPDATE:-}"
if [[ -z "$SIGN_UPDATE" ]]; then
  while IFS= read -r candidate; do SIGN_UPDATE="$candidate"; break; done < <(
    find "$ROOT/.build/artifacts" -type f -name sign_update -print 2>/dev/null | sort
  )
fi
[[ -x "$SIGN_UPDATE" ]] || { echo "Sparkle 2.10.0 sign_update not found" >&2; exit 2; }

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

SIGNATURE="$("$SIGN_UPDATE" --ed-key-file "$KEY" -p "$ARCHIVE")"
"$SIGN_UPDATE" --ed-key-file "$KEY" --verify "$ARCHIVE" "$SIGNATURE"
printf 'X' | dd of="$TAMPERED" bs=1 seek=7 conv=notrunc 2>/dev/null
if "$SIGN_UPDATE" --ed-key-file "$KEY" --verify "$TAMPERED" "$SIGNATURE"; then
  echo "Sparkle accepted a tampered update archive" >&2
  exit 1
fi
printf 'Sparkle rejected the tampered archive and accepted the intact fixture.\n'
