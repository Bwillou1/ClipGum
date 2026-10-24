# Phase 5 validation matrix

| Requirement | Automated coverage | Requires real macOS release validation |
| --- | --- | --- |
| Zero outbound copy/transform/paste | XCTest explicit cycle with request-recording URL protocol; protected-source network-call audit | Network-emulated/offline fresh-profile cycle |
| No content in app logs/diagnostics/crash reporting | Closed diagnostic enums and schema, exact JSON tests, source audit for logging/crash handlers | Review macOS's own crash-report privacy settings; OS reports are outside ClipGum's telemetry boundary |
| Diagnostics default-off/inspect/clear | XCTest defaults, schema, p50/p95, peak RAM, bounded storage, clear/disable behavior | Preferences and one-click Clear All Data UI walkthrough |
| Sparkle HTTPS/EdDSA/channel policy | XCTest metadata/key/URL/channel tests; signed-feed and pre-extraction plist checks | Signed stable/beta appcast UI and installation tests |
| Tampered update rejection | Sparkle `sign_update --verify` integration with intact and altered archives | Full updater rejection before replacement-app installation |
| Verified model download | XCTest HTTPS/path/size/RAM checks, mock transport, byte/SHA mismatch deletion, atomic install | Real publisher manifest, large-model download, hash/provenance review, local load |
| Hardened/minimal entitlements | Exact entitlement allowlist in XCTest and bundle validator; forbidden-key checks | Developer ID signature inspection and Gatekeeper behavior |
| DMG/Cask/notary/SBOM | Script syntax, DMG layout/signing steps, automatic SHA, CycloneDX generation | Actual Apple notarization, stapling, Gatekeeper, clean DMG/Cask install |
| Fresh-profile permission recovery | Existing non-destructive Accessibility-denial XCTest and recovery-guide tests | New macOS user profile protocol in `FRESH_PROFILE.md` |
| First-run/model readiness | Onboarding-state and synthetic readiness XCTest | Three-step walkthrough, TCC behavior, physical Apple Silicon/RAM/model testing |

A green CI run means automated compilation/tests/package structure passed on the CI image. It does not mean that a notarized release was produced, a fresh user completed installation, a real model was downloaded/loaded, or a full Sparkle update was installed.
