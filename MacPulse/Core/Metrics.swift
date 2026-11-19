import Foundation

enum MemoryPressure: String, Codable {
    case normal, warning, critical, unknown

    var title: String {
        switch self {
        case .normal: return "Normal"
        case .warning: return "Elevated"
        case .critical: return "High"
        case .unknown: return "Unavailable"
        }
    }
}

struct CPUCounters {
    let user: UInt32
    let system: UInt32
    let idle: UInt32
    let nice: UInt32

    func reading(since previous: CPUCounters) -> CPUReading? {
        // Kernel counters wrap; wrapping subtraction preserves the interval.
        let userDelta = Double(user &- previous.user) + Double(nice &- previous.nice)
        let systemDelta = Double(system &- previous.system)
        let idleDelta = Double(idle &- previous.idle)
        let total = userDelta + systemDelta + idleDelta
        guard total > 0 else { return nil }
        return CPUReading(user: 100 * userDelta / total, system: 100 * systemDelta / total)
    }
}

struct CPUReading {
    let user: Double
    let system: Double
    var total: Double { min(100, max(0, user + system)) }
    var idle: Double { max(0, 100 - total) }
}

struct MemoryReading {
    let total: UInt64
    let app: UInt64
    let wired: UInt64
    let compressed: UInt64
    let cached: UInt64
    let pressure: MemoryPressure

    var used: UInt64 { min(total, app + wired + compressed) }
    var available: UInt64 { total - used }
    var percent: Double { total > 0 ? Double(used) / Double(total) * 100 : 0 }

    static func fromPages(total: UInt64, pageSize: UInt64, internalPages: UInt64,
                          purgeable: UInt64, wired: UInt64, compressed: UInt64,
                          external: UInt64, pressure: MemoryPressure) -> MemoryReading {
        MemoryReading(total: total, app: (internalPages > purgeable ? internalPages - purgeable : 0) * pageSize,
                      wired: wired * pageSize, compressed: compressed * pageSize,
                      cached: (external + purgeable) * pageSize, pressure: pressure)
    }
}

struct DiskReading {
    let total: UInt64
    let available: UInt64
    var usedPercent: Double { total > 0 ? 100 * Double(total - min(total, available)) / Double(total) : 0 }
}

struct SystemSnapshot {
    let date: Date
    let cpu: CPUReading?
    let memory: MemoryReading?
    let swapUsed: UInt64?
    let disk: DiskReading?
    let uptime: TimeInterval
    let thermal: String
    let warnings: [String]

    var headline: String {
        if memory?.pressure == .critical { return "Your Mac is short on memory." }
        if memory?.pressure == .warning { return "Memory is working harder." }
        if thermal == "Serious" || thermal == "Critical" { return "Your Mac is running warm." }
        if let cpu, cpu.total >= 80 { return "Your processor is busy." }
        if cpu != nil && memory?.pressure == .normal { return "Your Mac has room to breathe." }
        return "Getting a clearer picture of your Mac."
    }

    var explanation: String {
        if memory?.pressure == .critical {
            return "macOS is struggling to make room. Review the largest memory users and close apps you no longer need."
        }
        if memory?.pressure == .warning {
            return "macOS is reclaiming memory. Check the memory leaders if your Mac feels slow; high RAM use alone is normal."
        }
        if thermal == "Serious" || thermal == "Critical" {
            return "macOS reports thermal strain. Give demanding tasks a break and make sure your Mac has airflow."
        }
        if let cpu, cpu.total >= 80 {
            return "A busy CPU is expected during demanding work. Check the process list if this continues while you are idle."
        }
        return "Look at CPU for current activity and memory pressure for how comfortably macOS is managing RAM."
    }
}

struct HistoryPoint: Identifiable {
    let date: Date
    let cpu: Double?
    let memory: Double?
    var id: Date { date }
}

enum MetricFormat {
    static func bytes(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: bytes), countStyle: .memory)
    }

    static func percent(_ value: Double?) -> String {
        value.map { String(format: "%.0f%%", $0) } ?? "—"
    }

    static func uptime(_ seconds: TimeInterval) -> String {
        let hours = Int(max(0, seconds)) / 3600
        return hours >= 24 ? "\(hours / 24)d \(hours % 24)h" : "\(hours)h \(Int(max(0, seconds)) / 60 % 60)m"
    }
}
