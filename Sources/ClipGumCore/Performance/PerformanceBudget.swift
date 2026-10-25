import Darwin
import Foundation

public enum CoreProcessMemory {
    public static func residentBytes() -> UInt64? {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info>.stride / MemoryLayout<natural_t>.stride
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), rebound, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return UInt64(info.resident_size)
    }
}

public enum ThermalBudget {
    /// Caps generation without changing the deterministic pipeline. The
    /// caller can use `requiresDeterministicFallback` for critical thermal
    /// pressure; no thermal notification or polling loop is installed.
    public static func maximumTokens(
        requested: Int,
        thermalState: ProcessInfo.ThermalState = ProcessInfo.processInfo.thermalState
    ) -> Int {
        let bounded = min(512, max(1, requested))
        switch thermalState {
        case .nominal: return bounded
        case .fair: return min(bounded, 256)
        case .serious: return min(bounded, 128)
        case .critical: return min(bounded, 32)
        @unknown default: return min(bounded, 128)
        }
    }

    public static func requiresDeterministicFallback(
        thermalState: ProcessInfo.ThermalState = ProcessInfo.processInfo.thermalState
    ) -> Bool {
        thermalState == .critical
    }
}

/// A one-shot, cancellable inactivity scheduler. It is used only while a
/// loaded model is waiting for its next explicit operation; there is no
/// repeating timer and no work after cancellation/quiescence.
public final class MemoryCompactor: @unchecked Sendable {
    private let lock = NSLock()
    private var task: Task<Void, Never>?

    public init() {}

    public func schedule(
        after timeout: TimeInterval,
        operation: @escaping @Sendable () async -> Void
    ) {
        cancel()
        let boundedTimeout = max(0.1, timeout)
        let newTask = Task {
            do {
                try await Task.sleep(nanoseconds: UInt64(boundedTimeout * 1_000_000_000))
            } catch {
                return
            }
            await operation()
        }
        lock.lock()
        task = newTask
        lock.unlock()
    }

    public func cancel() {
        lock.lock()
        let oldTask = task
        task = nil
        lock.unlock()
        oldTask?.cancel()
    }

    public var isScheduled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return task != nil
    }

    deinit {
        task?.cancel()
    }
}
