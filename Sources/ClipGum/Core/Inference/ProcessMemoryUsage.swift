import Darwin
import Foundation

enum ProcessMemoryUsage {
    /// Current resident size for the whole ClipGum process, not a claim about
    /// model-only allocation. The menu presents it with that qualification.
    static func residentBytes() -> UInt64? {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info>.stride / MemoryLayout<natural_t>.stride
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                task_info(
                    mach_task_self_,
                    task_flavor_t(MACH_TASK_BASIC_INFO),
                    rebound,
                    &count
                )
            }
        }
        guard result == KERN_SUCCESS else {
            return nil
        }
        return UInt64(info.resident_size)
    }

    static func formatted(_ bytes: UInt64?) -> String {
        guard let bytes else {
            return "RAM unavailable"
        }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .memory
        formatter.includesUnit = true
        return formatter.string(fromByteCount: Int64(min(bytes, UInt64(Int64.max))))
    }
}
