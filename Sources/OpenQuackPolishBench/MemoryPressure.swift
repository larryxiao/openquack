import Foundation
import Darwin
import Darwin.Mach

/// Snapshot of system-wide memory state. All values in bytes unless noted.
/// Source: host_statistics64(HOST_VM_INFO64). Sampling these deltas tells us
/// whether the polish model is causing the OS to compress / page (≈ thrash).
public struct MemorySnapshot: Sendable {
    public let freeBytes: UInt64
    public let activeBytes: UInt64
    public let inactiveBytes: UInt64
    public let wiredBytes: UInt64
    public let compressedBytes: UInt64
    public let pageins: UInt64       // cumulative since boot
    public let pageouts: UInt64
    public let compressions: UInt64

    public var usedBytes: UInt64 { activeBytes + inactiveBytes + wiredBytes + compressedBytes }
}

public enum MemoryPressure {
    public static func snapshot() -> MemorySnapshot? {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &stats) { ptr -> kern_return_t in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, rebound, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }

        let pageSize = UInt64(vm_kernel_page_size)
        return MemorySnapshot(
            freeBytes:       UInt64(stats.free_count) * pageSize,
            activeBytes:     UInt64(stats.active_count) * pageSize,
            inactiveBytes:   UInt64(stats.inactive_count) * pageSize,
            wiredBytes:      UInt64(stats.wire_count) * pageSize,
            compressedBytes: UInt64(stats.compressor_page_count) * pageSize,
            pageins:         UInt64(stats.pageins),
            pageouts:        UInt64(stats.pageouts),
            compressions:    UInt64(stats.compressions)
        )
    }

    public struct Delta: Sendable {
        public let freeDeltaBytes:       Int64    // negative = memory was consumed
        public let usedDeltaBytes:       Int64    // positive = pressure went up
        public let compressedDeltaBytes: Int64
        public let pageinsDelta:         Int64
        public let pageoutsDelta:        Int64
        public let compressionsDelta:    Int64
    }

    public static func delta(from a: MemorySnapshot, to b: MemorySnapshot) -> Delta {
        Delta(
            freeDeltaBytes:       Int64(b.freeBytes) - Int64(a.freeBytes),
            usedDeltaBytes:       Int64(b.usedBytes) - Int64(a.usedBytes),
            compressedDeltaBytes: Int64(b.compressedBytes) - Int64(a.compressedBytes),
            pageinsDelta:         Int64(b.pageins) - Int64(a.pageins),
            pageoutsDelta:        Int64(b.pageouts) - Int64(a.pageouts),
            compressionsDelta:    Int64(b.compressions) - Int64(a.compressions)
        )
    }
}
