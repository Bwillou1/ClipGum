#!/usr/bin/env bash
set -euo pipefail

DMG_PATH="${1:?usage: Build/generate_cask.sh ClipGum.dmg VERSION https://.../ClipGum.dmg [output]}"
VERSION="${2:?release version required}"
DOWNLOAD_URL="${3:?HTTPS download URL required}"
OUTPUT="${4:-$(dirname "$DMG_PATH")/clipgum.rb}"
[[ "$VERSION" =~ ^[0-9A-Za-z.-]+$ ]] || { echo "Unsafe cask version" >&2; exit 2; }
[[ "$DOWNLOAD_URL" == https://* ]] || { echo "The cask URL must use HTTPS" >&2; exit 2; }
[[ "$DOWNLOAD_URL" != *'"'* && "$DOWNLOAD_URL" != *"'"* && "$DOWNLOAD_URL" != *[[:space:]]* ]] || {
  echo "The cask URL must not contain quotes or whitespace" >&2
  exit 2
}
SHA256="$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')"
[[ "$SHA256" =~ ^[0-9a-f]{64}$ ]] || { echo "SHA-256 generation failed" >&2; exit 1; }

cat >"$OUTPUT" <<CASK
cask "clipgum" do
  version "$VERSION"
  sha256 "$SHA256"

  url "$DOWNLOAD_URL"
  name "ClipGum"
  desc "Explicit, local-only smart paste for Apple Silicon"
  homepage "https://github.com/Bwillou1/ClipGum"

  depends_on arch: :arm64
  depends_on macos: ">= :sonoma"

  app "ClipGum.app"

  zap trash: [
    "~/Library/Containers/com.clipgum.ClipGum",
    "~/Library/Preferences/com.clipgum.ClipGum.plist",
    "~/Library/Saved Application State/com.clipgum.ClipGum.savedState",
  ]
end
CASK
printf 'Generated %s with SHA-256 %s\n' "$OUTPUT" "$SHA256"
