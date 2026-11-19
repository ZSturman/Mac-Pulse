import Foundation
import Darwin

/// Callers serialize all access on their sampling queue, including reset and destruction.
/// Both targets compile this directly; no IPC or App Group is required.
final class SystemSampler: @unchecked Sendable {
    private let host = mach_host_self()
    private var previousCPU: CPUCounters?

    deinit { mach_port_deallocate(mach_task_self_, host) }

    func reset() { previousCPU = nil }

    func sample(includeDisk: Bool = true) -> SystemSnapshot {
        var warnings: [String] = []
        let counters = readCPU()
        let cpu = counters.flatMap { current in previousCPU.flatMap { current.reading(since: $0) } }
        previousCPU = counters
        if counters == nil { warnings.append("CPU activity is unavailable.") }
        let memory = readMemory()
        if memory == nil { warnings.append("Memory statistics are unavailable.") }
        return SystemSnapshot(date: Date(), cpu: cpu, memory: memory, swapUsed: readSwap(),
                              disk: includeDisk ? readDisk() : nil,
                              uptime: ProcessInfo.processInfo.systemUptime,
                              thermal: thermalState, warnings: warnings)
    }

    private func readCPU() -> CPUCounters? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return CPUCounters(user: info.cpu_ticks.0, system: info.cpu_ticks.1,
                           idle: info.cpu_ticks.2, nice: info.cpu_ticks.3)
    }

    private func readMemory() -> MemoryReading? {
        var info = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        var pageSize: vm_size_t = 0
        guard result == KERN_SUCCESS, host_page_size(host, &pageSize) == KERN_SUCCESS else { return nil }
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let pressureResult = sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0)
        let pressure: MemoryPressure
        switch pressureResult == 0 ? level : 0 {
        case 1: pressure = .normal
        case 2: pressure = .warning
        case 4: pressure = .critical
        default: pressure = .unknown
        }
        return MemoryReading.fromPages(total: ProcessInfo.processInfo.physicalMemory,
            pageSize: UInt64(pageSize), internalPages: UInt64(info.internal_page_count),
            purgeable: UInt64(info.purgeable_count), wired: UInt64(info.wire_count),
            compressed: UInt64(info.compressor_page_count), external: UInt64(info.external_page_count),
            pressure: pressure)
    }

    private func readSwap() -> UInt64? {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return nil }
        return usage.xsu_used
    }

    private func readDisk() -> DiskReading? {
        // The writable home volume is more useful than the sealed system volume on APFS.
        guard let values = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
              let total = values[.systemSize] as? NSNumber,
              let free = values[.systemFreeSize] as? NSNumber else { return nil }
        return DiskReading(total: total.uint64Value, available: free.uint64Value)
    }

    private var thermalState: String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return "Nominal"
        case .fair: return "Warm"
        case .serious: return "Serious"
        case .critical: return "Critical"
        @unknown default: return "Unknown"
        }
    }
}
