# Phase 7 benchmark procedure

## Automated

Run `swift test` on a macOS host. The separate `ClipGumPerformanceTests` target
records `XCTClockMetric` and `XCTMemoryMetric` for the deterministic 1 MiB
workload and checks virtual idle behavior. On a controlled host, set
`CLIPGUM_ENFORCE_PERF_BUDGETS=1` to enforce the 5 ms cleaning goal.

`Build/validate_phase7.sh` checks the mobile plist/extension boundaries,
local-only transport declarations, shared-target specification, and required
security documents.

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
