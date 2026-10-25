import ClipGumCore
import Foundation
import XCTest

final class Phase7PerformanceTests: XCTestCase {
    func testOneMegabyteDeterministicCleaningBenchmark() {
        let line = "token=Abcd1234efgh5678 https://example.com/?utm_source=x&id=1\n"
        let payload = String(repeating: line, count: (1_048_576 / line.utf8.count) + 1)
        let options = XCTMeasureOptions()
        options.iterationCount = 5
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()], options: options) {
            _ = DeterministicTransforms.sanitize(payload)
        }
        // CI hardware is variable. Set CLIPGUM_ENFORCE_PERF_BUDGETS=1 on a
        // controlled host to additionally enforce the <5 ms product goal.
        if ProcessInfo.processInfo.environment["CLIPGUM_ENFORCE_PERF_BUDGETS"] == "1" {
            let started = DispatchTime.now().uptimeNanoseconds
            _ = DeterministicTransforms.sanitize(payload)
            let elapsedMilliseconds = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
            XCTAssertLessThan(elapsedMilliseconds, 5)
        }
    }

    @MainActor
    func testVirtual72HourIdleHasNoImplicitP2PWork() {
        let service = LocalP2PService()
        // This is virtual idle coverage, not a claim of a physical 72-hour
        // thermal run. No start call means no listener, browser, or timer.
        for _ in 0..<(72 * 60 * 60) {
            XCTAssertFalse(service.isRunning)
        }
        service.stop()
        XCTAssertEqual(service.discoveredDevices, [])
    }

    func testColdStartBenchmarkEntryPointIsDocumented() throws {
        // A process cold start requires an installed app host and is not the
        // same as constructing a value type in XCTest. Keep this explicit skip
        // rather than publishing a misleading mobile/macOS launch number.
        throw XCTSkip("Measure signed macOS/iOS process cold starts with Build/phase7_benchmarks.md.")
    }
}
