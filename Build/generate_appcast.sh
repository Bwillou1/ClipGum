#!/usr/bin/env bash
set -euo pipefail

DMG_PATH="${1:?DMG path required}"
VERSION="${2:?display version required}"
BUILD_NUMBER="${3:?Sparkle numeric/build version required}"
CHANNEL="${4:-stable}"
DOWNLOAD_URL="${5:?HTTPS DMG URL required}"
OUTPUT="${6:-$(dirname "$DMG_PATH")/appcast.xml}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

[[ "$CHANNEL" == stable || "$CHANNEL" == beta ]] || { echo "Channel must be stable or beta" >&2; exit 2; }
[[ "$VERSION" =~ ^[0-9A-Za-z.-]+$ && "$BUILD_NUMBER" =~ ^[0-9A-Za-z.-]+$ ]] || {
  echo "Unsafe appcast version" >&2; exit 2;
}
[[ "$DOWNLOAD_URL" == https://* ]] || { echo "Appcast enclosure must use HTTPS" >&2; exit 2; }
[[ "$DOWNLOAD_URL" != *'&'* && "$DOWNLOAD_URL" != *'"'* && "$DOWNLOAD_URL" != *"'"* \
  && "$DOWNLOAD_URL" != *'<'* && "$DOWNLOAD_URL" != *'>'* && "$DOWNLOAD_URL" != *[[:space:]]* ]] || {
  echo "Appcast URL contains unsupported XML characters" >&2; exit 2;
}

SIGN_UPDATE="${SPARKLE_SIGN_UPDATE:-}"
if [[ -z "$SIGN_UPDATE" ]]; then
  while IFS= read -r candidate; do SIGN_UPDATE="$candidate"; break; done < <(
    find "$ROOT/.build/artifacts" -type f -path '*/Sparkle/bin/sign_update' -print 2>/dev/null | sort
  )
fi
[[ -x "$SIGN_UPDATE" ]] || { echo "Set SPARKLE_SIGN_UPDATE to Sparkle 2.10.0's sign_update" >&2; exit 2; }

SIGN=("$SIGN_UPDATE")
if [[ -n "${SPARKLE_ED_KEY_FILE:-}" ]]; then
  SIGN+=(--ed-key-file "$SPARKLE_ED_KEY_FILE")
elif [[ -n "${SPARKLE_KEYCHAIN_ACCOUNT:-}" ]]; then
  SIGN+=(--account "$SPARKLE_KEYCHAIN_ACCOUNT")
fi

SIGNATURE="$("${SIGN[@]}" -p "$DMG_PATH")"
[[ -n "$SIGNATURE" ]] || { echo "Sparkle did not produce an EdDSA signature" >&2; exit 1; }
LENGTH="$(stat -f%z "$DMG_PATH")"
PUBDATE="$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')"
NOTES="ClipGum $VERSION. See the accompanying beta-testing and release documentation."
if [[ -n "${RELEASE_NOTES_FILE:-}" ]]; then
  NOTES="$(sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' "$RELEASE_NOTES_FILE")"
fi
CHANNEL_XML=""
if [[ "$CHANNEL" == beta ]]; then
  CHANNEL_XML="        <sparkle:channel>beta</sparkle:channel>"
fi

cat >"$OUTPUT" <<APPCAST
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>ClipGum Updates</title>
    <description>Signed stable and explicitly tagged beta updates for ClipGum.</description>
    <item>
      <title>ClipGum $VERSION</title>
      <pubDate>$PUBDATE</pubDate>
      <description sparkle:descriptionFormat="plain-text">$NOTES</description>
      <sparkle:minimumSystemVersion>14.0.0</sparkle:minimumSystemVersion>
      <sparkle:hardwareRequirements>arm64</sparkle:hardwareRequirements>
$CHANNEL_XML
      <enclosure
        url="$DOWNLOAD_URL"
        length="$LENGTH"
        type="application/octet-stream"
        sparkle:version="$BUILD_NUMBER"
        sparkle:shortVersionString="$VERSION"
        sparkle:edSignature="$SIGNATURE" />
    </item>
  </channel>
</rss>
APPCAST

# SURequireSignedFeed is enabled, so signing only the enclosure is insufficient.
"${SIGN[@]}" "$OUTPUT"
"${SIGN[@]}" --verify "$DMG_PATH" "$SIGNATURE"
"${SIGN[@]}" --verify "$OUTPUT"
printf 'Generated and verified signed %s appcast: %s\n' "$CHANNEL" "$OUTPUT"
