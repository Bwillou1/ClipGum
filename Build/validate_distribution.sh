#!/usr/bin/env bash
set -euo pipefail

APP_BUNDLE="${1:?usage: Build/validate_distribution.sh ClipGum.app [--development|--production]}"
MODE="${2:---development}"
[[ "$MODE" == --development || "$MODE" == --production ]] || { echo "Invalid validation mode" >&2; exit 2; }
[[ -d "$APP_BUNDLE/Contents/Frameworks/Sparkle.framework" ]] || { echo "Sparkle.framework is not embedded" >&2; exit 1; }
find "$APP_BUNDLE/Contents/Frameworks/Sparkle.framework" -type d -name 'InstallerLauncher.xpc' -print -quit | grep -q . \
  || { echo "Sparkle InstallerLauncher.xpc is missing" >&2; exit 1; }
[[ -f "$APP_BUNDLE/Contents/Resources/SBOM.json" ]] || { echo "SBOM is missing" >&2; exit 1; }
find "$APP_BUNDLE/Contents/Resources" -type f -name 'Sparkle.txt' -print -quit | grep -q . \
  || { echo "Embedded license resources are missing" >&2; exit 1; }
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
otool -L "$APP_BUNDLE/Contents/MacOS/ClipGum" | grep '@rpath/Sparkle.framework' >/dev/null \
  || { echo "Sparkle dynamic linkage is missing" >&2; exit 1; }

python3 - "$APP_BUNDLE" "$MODE" <<'PY'
import base64
import pathlib
import plistlib
import subprocess
import sys
import urllib.parse

app = pathlib.Path(sys.argv[1])
mode = sys.argv[2]
info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
result = subprocess.run(
    ["codesign", "-d", "--entitlements", ":-", str(app)],
    check=True, capture_output=True,
)
entitlements = plistlib.loads(result.stdout)
expected = {
    "com.apple.security.app-sandbox",
    "com.apple.security.files.user-selected.read-only",
    "com.apple.security.network.client",
    "com.apple.security.temporary-exception.mach-lookup.global-name",
}
assert set(entitlements) == expected, f"Non-minimal main-app entitlements: {sorted(entitlements)}"
assert entitlements["com.apple.security.app-sandbox"] is True
assert entitlements["com.apple.security.files.user-selected.read-only"] is True
assert entitlements["com.apple.security.network.client"] is True
assert entitlements["com.apple.security.temporary-exception.mach-lookup.global-name"] == [
    "com.clipgum.ClipGum-spks", "com.clipgum.ClipGum-spki"
]
assert info["LSMinimumSystemVersion"] == "14.0"
assert info["SURequireSignedFeed"] is True
assert info["SUVerifyUpdateBeforeExtraction"] is True
assert info["SUEnableDownloaderService"] is False
assert info["SUEnableInstallerLauncherService"] is True
assert info["SUEnableSystemProfiling"] is False
assert info["SUSendProfileInfo"] is False
assert info["SUEnableJavaScript"] is False
assert info["SUAllowedURLSchemes"] == ["https"]
if mode == "--production":
    feed = info.get("SUFeedURL", "")
    key = info.get("SUPublicEDKey", "")
    feed_parts = urllib.parse.urlsplit(feed)
    assert feed_parts.scheme == "https" and feed_parts.hostname
    assert feed_parts.username is None and feed_parts.password is None
    assert len(base64.b64decode(key, validate=True)) == 32
    authority = subprocess.run(["codesign", "-dv", str(app)], check=True, capture_output=True).stderr.decode()
    assert "Developer ID Application" in authority
print(f"Validated {mode[2:]} bundle policy for {app}")
PY
