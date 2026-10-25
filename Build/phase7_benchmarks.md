# Phase 7 benchmark procedure

## Automated

Run `swift test` on a macOS host. The separate `ClipGumPerformanceTests` target
records `XCTClockMetric` and `XCTMemoryMetric` for the deterministic 1 MiB
workload and checks virtual idle behavior. On a controlled host, set
`CLIPGUM_ENFORCE_PERF_BUDGETS=1` to enforce the 5 ms cleaning goal.

`Build/validate_phase7.sh` checks the mobile plist/extension boundaries,
local-only transport declarations, shared-target specification, and required
security documents.

## Public design benchmarks — not timing results

These references informed the implementation boundaries; no proprietary source
was inspected and no comparative throughput/latency result is claimed.

| Area | Public reference | ClipGum decision |
| --- | --- | --- |
| Nearby transport | [Apple `MCSession`](https://developer.apple.com/documentation/multipeerconnectivity/mcsession), [Multipeer encryption preference](https://developer.apple.com/documentation/multipeerconnectivity/mcsession/encryptionpreference), and Apple's [Network framework migration mapping](https://developer.apple.com/forums/thread/776069) | MultipeerConnectivity supplies peer/session and encryption-preference abstractions. ClipGum instead uses `NWBrowser`/`NWListener`/`NWConnection` so its bounded frames, explicit one-peer lifetime, SAS handshake, and payload AEAD remain visible in the core state machine. This is an architecture comparison, not a measured claim that one framework is faster. |
| Handshake/channel patterns | [Noise Protocol Framework](https://noiseprotocol.org/noise.html) and [libsodium `crypto_kx`](https://libsodium.gitbook.io/doc/key_exchange) | Noise documents named X25519/ChaChaPoly/HKDF patterns; libsodium documents distinct receive/transmit keys and counter-compatible directional nonces. ClipGum adopts transcript binding, HKDF direction separation, and monotonically sequenced AEAD with CryptoKit, but its ephemeral-plus-SAS exchange is not advertised as Noise interoperable or formally audited. No libsodium code is linked. |
| iOS Action/Share Sheet providers | [Apple Action Extension guide](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/Action.html), [`NSItemProvider`](https://developer.apple.com/documentation/foundation/nsitemprovider), and [`NSExtensionContext`](https://developer.apple.com/documentation/foundation/nsextensioncontext) | The extension consumes only the host-supplied plain-text provider, displays a preview, and returns an explicit `NSExtensionItem`. It does not fetch URLs, inject JavaScript, open the containing app, or use the general pasteboard. Provider-specific physical behavior remains on the manual test matrix. |

## Manual process and device measurements

Record the exact commit, Xcode/SDK, device, OS, power state, thermal state, and
whether the app was signed/installed. Do not substitute a unit-test initializer
for a cold application launch.

1. Measure at least 30 cold launches of the macOS app and iOS companion after a
   fresh boot/profile. Report median and p95 separately against the <50 ms and
   <100 ms goals.
2. Benchmark 1 MiB cleaning with the same input fixture on both platforms;
   report median/p95 and peak resident memory against the <5 ms goal.
3. Run a 72-hour idle session with no handoff window. Inspect Network.framework
   connections, timers, resident memory, and payload buffers at the start/end.
   A virtual idle loop in XCTest is not evidence of a physical 72-hour result.
4. Repeat with thermal pressure and a user-selected CoreML model. The model
   file-size budget is not a substitute for runtime memory measurement.
5. For new major SDKs, rerun `Tests/Performance/README.md`'s compatibility
   checklist and inspect availability-gated APIs before changing deployment
   targets.

No benchmark result is included in the repository until it has been collected
on the relevant physical host.
