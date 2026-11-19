import Foundation
import Darwin

struct ProcessIdentity: Hashable {
    let pid: Int32
    let started: UInt64
}

struct ProcessApp: Equatable {
    enum Source: String {
        case executable = "Executable is inside the app bundle"
        case ancestor = "Found through the parent process chain"
    }

    let name: String
    let bundlePath: String
    let source: Source
}

struct ProcessReading: Identifiable {
    let id: ProcessIdentity
    let name: String
    let cpu: Double?
    let memory: UInt64
    let parentPID: Int32
    let executablePath: String?
    var parentName: String?
    var app: ProcessApp?

    var pid: Int32 { id.pid }
    var displayName: String { name.isEmpty ? "Process \(pid)" : name }
}

struct ProcessSample {
    let readings: [ProcessReading]
    let inaccessible: Int
    let enumerationFailed: Bool
}

/// Mutable baselines are confined to MonitorStore's serial sampling queue.
final class ProcessSampler: @unchecked Sendable {
    private struct Baseline {
        let started: UInt64
        let cpuTicks: UInt64
        let name: String
        let executablePath: String?
        let app: ProcessApp?
    }
    private var previous: [Int32: Baseline] = [:]
    private var previousTime: TimeInterval?
    private let nanosecondsPerTick: Double = {
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        return Double(timebase.numer) / Double(timebase.denom)
    }()

    func reset() {
        previous = [:]
        previousTime = nil
    }

    static func cpuPercent(current: UInt64, previous: UInt64, elapsed: TimeInterval,
                           nanosecondsPerTick: Double = 1) -> Double? {
        guard elapsed > 0, current >= previous, nanosecondsPerTick.isFinite, nanosecondsPerTick > 0 else { return nil }
        return Double(current - previous) * nanosecondsPerTick / 1_000_000_000 / elapsed * 100
    }

    func sample() -> ProcessSample {
        let now = ProcessInfo.processInfo.systemUptime
        let elapsed = previousTime.map { now - $0 }
        let capacity = proc_listallpids(nil, 0)
        guard capacity > 0 else {
            reset()
            return ProcessSample(readings: [], inaccessible: 0, enumerationFailed: true)
        }
        // Headroom handles processes starting between the count and enumeration calls.
        var pids = [pid_t](repeating: 0, count: Int(capacity) + 256)
        let byteCount = Int32(pids.count * MemoryLayout<pid_t>.size)
        let count = pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, byteCount) }
        guard count > 0 else {
            reset()
            return ProcessSample(readings: [], inaccessible: 0, enumerationFailed: true)
        }
        var next: [Int32: Baseline] = [:]
        var readings: [ProcessReading] = []
        var inaccessible = 0
        for pid in pids.prefix(min(Int(count), pids.count)) where pid > 0 {
            var info = proc_taskallinfo()
            let infoSize = Int32(MemoryLayout<proc_taskallinfo>.size)
            guard proc_pidinfo(pid, PROC_PIDTASKALLINFO, 0, &info, infoSize) == infoSize else {
                inaccessible += 1
                continue
            }
            let total = info.ptinfo.pti_total_user + info.ptinfo.pti_total_system
            let started = info.pbsd.pbi_start_tvsec * 1_000_000 + info.pbsd.pbi_start_tvusec
            let cpu: Double?
            if let old = previous[pid], old.started == started, let elapsed {
                // proc_taskinfo reports Mach absolute ticks, not nanoseconds (notably on Apple silicon).
                cpu = Self.cpuPercent(current: total, previous: old.cpuTicks, elapsed: elapsed,
                                      nanosecondsPerTick: nanosecondsPerTick)
            } else { cpu = nil }
            let name = withUnsafeBytes(of: info.pbsd.pbi_name) { raw in
                String(decoding: raw.prefix(while: { $0 != 0 }), as: UTF8.self)
            }
            let fallback = withUnsafeBytes(of: info.pbsd.pbi_comm) { raw in
                String(decoding: raw.prefix(while: { $0 != 0 }), as: UTF8.self)
            }
            let processName = name.isEmpty ? fallback : name
            let executablePath: String?
            let app: ProcessApp?
            if let old = previous[pid], old.started == started, old.name == processName {
                executablePath = old.executablePath
                app = old.app
            } else {
                executablePath = Self.executablePath(for: pid)
                app = executablePath.flatMap(Self.appContainingExecutable)
            }
            next[pid] = Baseline(started: started, cpuTicks: total, name: processName,
                                 executablePath: executablePath, app: app)
            readings.append(ProcessReading(id: ProcessIdentity(pid: pid, started: started),
                                            name: processName, cpu: cpu, memory: info.ptinfo.pti_resident_size,
                                            parentPID: Int32(bitPattern: info.pbsd.pbi_ppid),
                                            executablePath: executablePath, app: app))
        }
        Self.attributeApps(in: &readings)
        previous = next
        previousTime = now
        return ProcessSample(readings: readings, inaccessible: inaccessible, enumerationFailed: false)
    }

    private static func executablePath(for pid: Int32) -> String? {
        // PROC_PIDPATHINFO_MAXSIZE is a C expression that Swift cannot import.
        var buffer = [UInt8](repeating: 0, count: Int(MAXPATHLEN) * 4)
        let size = UInt32(buffer.count)
        let length = buffer.withUnsafeMutableBytes { proc_pidpath(pid, $0.baseAddress, size) }
        guard length > 0 else { return nil }
        return String(decoding: buffer.prefix(Int(length)).prefix(while: { $0 != 0 }), as: UTF8.self)
    }

    private static func appContainingExecutable(_ executablePath: String) -> ProcessApp? {
        let path = (executablePath as NSString).pathComponents
        // Walk outermost first so an embedded helper app is attributed to its containing app.
        for index in path.indices.dropLast() where path[index].hasSuffix(".app") && path[index + 1] == "Contents" {
            let bundlePath = NSString.path(withComponents: Array(path[...index]))
            guard let bundle = Bundle(path: bundlePath), bundle.bundleIdentifier != nil else { continue }
            let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
                ?? (path[index] as NSString).deletingPathExtension
            return ProcessApp(name: name, bundlePath: bundlePath, source: .executable)
        }
        return nil
    }

    static func attributeApps(in readings: inout [ProcessReading]) {
        let byPID = Dictionary(readings.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        for index in readings.indices {
            let process = readings[index]
            if let parent = byPID[process.parentPID], parent.id.started <= process.id.started {
                readings[index].parentName = parent.displayName
            }
            guard process.app == nil else { continue }
            var current = process
            var visited: Set<Int32> = [process.pid]
            // PID 1 adopts orphaned processes but gives no evidence about their app.
            while current.parentPID > 1, let parent = byPID[current.parentPID],
                  parent.id.started <= current.id.started, visited.insert(parent.pid).inserted {
                if let app = parent.app {
                    readings[index].app = ProcessApp(name: app.name, bundlePath: app.bundlePath, source: .ancestor)
                    break
                }
                current = parent
            }
        }
    }
}
