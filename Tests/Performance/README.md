# Phase 7 performance and compatibility harness

`Phase7PerformanceTests.swift` is a separate SwiftPM test target. It records
clock/memory metrics for a 1 MiB deterministic cleaning workload and checks that
an inactive P2P service remains inactive across a virtual 72-hour idle loop.

The product budgets are:

- macOS cold process start: **<50 ms** goal;
- iOS cold process start: **<100 ms** goal;
- 1 MiB deterministic regex/URL cleaning: **<5 ms** goal on a controlled host;
- 72-hour physical idle: no listener, browser, retry, timer, or retained payload
  growth.

Set `CLIPGUM_ENFORCE_PERF_BUDGETS=1` only on a controlled benchmark host to turn
the cleaning goal into a failing assertion. CI records metrics but does not
claim hardware-independent timing. Cold process launch, physical thermal runs,
and iOS measurements require installed app hosts and are intentionally not
reported as passing results.

## SDK compatibility checklist

For each new macOS/iOS major SDK:

1. Resolve the pinned package graph and compile `ClipGumCore` plus the macOS app.
2. Regenerate the mobile project and compile all three mobile targets.
3. Verify `Network.framework` Bonjour permission declarations and test a local
   network permission denial/recovery cycle.
4. Run the packet, SAS, AEAD tamper/replay, backup, and extension-isolation tests.
5. Review availability-gated CoreML and JavaScriptCore APIs; do not enable a new
   network or pasteboard entitlement as part of SDK migration.
