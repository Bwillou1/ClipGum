#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

python3 - <<'PY'
from pathlib import Path
import plistlib
import re

root = Path.cwd()
for relative in [
    'Targets/ClipGumMobile/Resources/Info.plist',
    'Targets/ClipGumMobile/ActionExtension/Info.plist',
    'Targets/ClipGumMobile/KeyboardExtension/Info.plist',
]:
    with (root / relative).open('rb') as handle:
        plistlib.load(handle)

app = plistlib.loads((root / 'Targets/ClipGumMobile/Resources/Info.plist').read_bytes())
assert '_clipgum._tcp' in app['NSBonjourServices']
assert app['NSLocalNetworkUsageDescription']
action = plistlib.loads((root / 'Targets/ClipGumMobile/ActionExtension/Info.plist').read_bytes())
keyboard = plistlib.loads((root / 'Targets/ClipGumMobile/KeyboardExtension/Info.plist').read_bytes())
assert action['NSExtension']['NSExtensionPointIdentifier'] == 'com.apple.ui-services'
assert keyboard['NSExtension']['NSExtensionPointIdentifier'] == 'com.apple.keyboard-service'
assert keyboard['NSExtension']['NSExtensionAttributes']['RequestsOpenAccess'] is True

mac_app = plistlib.loads((root / 'Resources/Info.plist').read_bytes())
assert '_clipgum._tcp' in mac_app['NSBonjourServices']
assert mac_app['NSLocalNetworkUsageDescription']
mac_entitlements = plistlib.loads((root / 'Resources/ClipGum.entitlements').read_bytes())
assert mac_entitlements['com.apple.security.network.server'] is True
assert mac_entitlements['com.apple.security.network.client'] is True

provenance = (root / 'Vendor/Argon2/UPSTREAM.md').read_text()
assert 'bcf667c8ee59ad6014bdac1474b5e717a0b95844' in provenance
assert (root / 'Vendor/Argon2/LICENSE').exists()

p2p = '\n'.join(path.read_text() for path in (root / 'Sources/ClipGumCore/Sync/P2P').glob('*.swift'))
for forbidden in ['URLSession', 'CloudKit', 'CKContainer', 'Firebase', 'AWSSync']:
    assert forbidden not in p2p, forbidden
assert 'NWListener' in p2p and 'NWBrowser' in p2p and 'includePeerToPeer' in p2p
assert 'Curve25519.KeyAgreement' in p2p and 'ChaChaPoly' in p2p

action_source = (root / 'Targets/ClipGumMobile/ActionExtension/ActionViewController.swift').read_text()
assert 'UIPasteboard' not in action_source
assert 'maximumSharedTextBytes' in action_source
keyboard_source = (root / 'Targets/ClipGumMobile/KeyboardExtension/KeyboardViewController.swift').read_text()
assert keyboard_source.count('UIPasteboard.general.string') == 1
assert keyboard_source.index('pasteCleanTapped') < keyboard_source.index('UIPasteboard.general.string')
inference_source = (root / 'Targets/ClipGumMobile/MobileInferenceEngine.swift').read_text()
assert 'model.transform(cleanedInput)' in inference_source
for forbidden in ['URLSession', 'CloudKit', 'Firebase']:
    assert forbidden not in inference_source

spec = (root / 'Targets/ClipGumMobile/project.yml').read_text()
for target in ['ClipGumMobile:', 'ClipGumMobileAction:', 'ClipGumMobileKeyboard:']:
    assert target in spec
assert 'product: ClipGumCore' in spec
assert '- target: ClipGumMobileAction' in spec
assert '- target: ClipGumMobileKeyboard' in spec

for path in [root / 'P2P_SECURITY.md', root / 'MOBILE.md', root / 'Build/phase7_benchmarks.md']:
    assert path.exists(), path
print('Phase 7 mobile, local-only transport, extension, and documentation contracts passed.')
PY

bash -n Build/validate_phase7.sh
