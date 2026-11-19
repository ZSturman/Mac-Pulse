import Foundation

/// Conditions worth interrupting for, in display priority order.
enum AlertKind: String, CaseIterable {
    case memory, thermal, cpu, storage

    var icon: String {
        switch self {
        case .memory: return "memorychip"
        case .thermal: return "thermometer.high"
        case .cpu: return "cpu"
        case .storage: return "internaldrive"
        }
    }

    /// Process rows only explain activity-driven alerts.
    var involvesProcesses: Bool { self != .storage }
}

struct SystemAlert: Identifiable, Equatable {
    let kind: AlertKind
    let isCritical: Bool
    let title: String
    let message: String
    /// Compact text for the menu bar, e.g. "CPU 93%".
    let shortText: String
    var id: AlertKind { kind }
}

/// When the menu bar item appears.
enum MenuBarMode: String, CaseIterable, Identifiable {
    case alerts, always, never
    var id: String { rawValue }

    var title: String {
        switch self {
        case .alerts: return "Only when something needs attention"
        case .always: return "Always"
        case .never: return "Never"
        }
    }

    func isInserted(hasAlerts: Bool) -> Bool {
        self == .always || (self == .alerts && hasAlerts)
    }
}

/// Turns live snapshots into sustained alerts. Brief spikes are ignored, clearing waits for the
/// condition to settle, and each kind is announced at most once per cooldown unless it becomes critical.
/// Times are monotonic seconds (system uptime).
struct AlertMonitor {
    static let cpuWindow: TimeInterval = 60
    static let cpuClearMargin = 10.0
    static let memoryOnset: TimeInterval = 30
    static let settleTime: TimeInterval = 30
    static let storageLimit: UInt64 = 10_000_000_000
    static let storageClearLimit: UInt64 = 15_000_000_000
    static let storageCriticalLimit: UInt64 = 2_000_000_000
    static let notificationCooldown: TimeInterval = 30 * 60

    private enum Condition {
        case present(SystemAlert), absent, unknown
    }

    private(set) var alerts: [SystemAlert] = []
    private var cpuSamples: [(time: TimeInterval, value: Double)] = []
    private var onsetStart: [AlertKind: TimeInterval] = [:]
    private var clearStart: [AlertKind: TimeInterval] = [:]
    private var lastAnnounced: [AlertKind: (time: TimeInterval, critical: Bool)] = [:]

    /// Forgets current conditions (for example while paused) but keeps the announcement cooldown.
    mutating func reset() {
        alerts = []
        cpuSamples = []
        onsetStart = [:]
        clearStart = [:]
    }

    /// Updates `alerts` and returns the alerts that should be announced now.
    mutating func update(with snapshot: SystemSnapshot, at time: TimeInterval, cpuThreshold: Double) -> [SystemAlert] {
        var next = Dictionary(uniqueKeysWithValues: alerts.map { ($0.kind, $0) })
        resolve(.cpu, cpuCondition(snapshot, at: time, threshold: cpuThreshold, active: next[.cpu] != nil),
                onset: 0, settle: 0, at: time, into: &next)
        resolve(.memory, memoryCondition(snapshot), onset: Self.memoryOnset, settle: Self.settleTime, at: time, into: &next)
        resolve(.thermal, thermalCondition(snapshot), onset: 0, settle: Self.settleTime, at: time, into: &next)
        resolve(.storage, storageCondition(snapshot, active: next[.storage] != nil), onset: 0, settle: 0, at: time, into: &next)

        let previous = Dictionary(uniqueKeysWithValues: alerts.map { ($0.kind, $0) })
        alerts = AlertKind.allCases.compactMap { next[$0] }
        return alerts.filter { alert in
            let escalated = previous[alert.kind].map { !$0.isCritical && alert.isCritical } ?? true
            guard escalated else { return false }
            if let last = lastAnnounced[alert.kind], time - last.time < Self.notificationCooldown,
               last.critical || !alert.isCritical {
                return false
            }
            lastAnnounced[alert.kind] = (time, alert.isCritical)
            return true
        }
    }

    private mutating func resolve(_ kind: AlertKind, _ condition: Condition, onset: TimeInterval,
                                  settle: TimeInterval, at time: TimeInterval, into next: inout [AlertKind: SystemAlert]) {
        switch condition {
        case .unknown:
            return
        case .present(let alert):
            clearStart[kind] = nil
            if next[kind] != nil {
                next[kind] = alert
                return
            }
            let start = onsetStart[kind] ?? time
            onsetStart[kind] = start
            if alert.isCritical || time - start >= onset {
                next[kind] = alert
                onsetStart[kind] = nil
            }
        case .absent:
            onsetStart[kind] = nil
            guard next[kind] != nil else { return }
            let start = clearStart[kind] ?? time
            clearStart[kind] = start
            if time - start >= settle {
                next[kind] = nil
                clearStart[kind] = nil
            }
        }
    }

    private mutating func cpuCondition(_ snapshot: SystemSnapshot, at time: TimeInterval,
                                       threshold: Double, active: Bool) -> Condition {
        if let cpu = snapshot.cpu?.total {
            // A long gap (sleep, pause) means the old samples no longer describe a continuous minute.
            if let last = cpuSamples.last, time - last.time > 30 { cpuSamples.removeAll() }
            cpuSamples.append((time, cpu))
        }
        cpuSamples.removeAll { $0.time < time - Self.cpuWindow }
        guard let first = cpuSamples.first, time - first.time >= Self.cpuWindow * 0.75 else {
            return active ? .unknown : .absent
        }
        let average = cpuSamples.reduce(0) { $0 + $1.value } / Double(cpuSamples.count)
        guard average >= (active ? threshold - Self.cpuClearMargin : threshold) else { return .absent }
        let current = snapshot.cpu?.total ?? average
        return .present(SystemAlert(kind: .cpu, isCritical: false, title: "Your processor is busy",
            message: "CPU use has averaged \(MetricFormat.percent(average)) for the past minute. Open Mac Pulse to see which apps are responsible.",
            shortText: "CPU \(MetricFormat.percent(current))"))
    }

    private func memoryCondition(_ snapshot: SystemSnapshot) -> Condition {
        switch snapshot.memory?.pressure {
        case .normal: return .absent
        case .warning:
            return .present(SystemAlert(kind: .memory, isCritical: false, title: "Memory is under pressure",
                message: "macOS is compressing and swapping memory to make room. Quitting apps you are not using will help.",
                shortText: "Memory"))
        case .critical:
            return .present(SystemAlert(kind: .memory, isCritical: true, title: "Your Mac is short on memory",
                message: "Memory pressure is high and your Mac may slow down. Save your work and quit apps you no longer need.",
                shortText: "Memory"))
        case .unknown, nil: return .unknown
        }
    }

    private func thermalCondition(_ snapshot: SystemSnapshot) -> Condition {
        switch snapshot.thermal {
        case "Nominal", "Warm": return .absent
        case "Serious":
            return .present(SystemAlert(kind: .thermal, isCritical: false, title: "Your Mac is running hot",
                message: "macOS reports serious thermal pressure and may slow your Mac to cool it. Check for busy apps and keep the vents clear.",
                shortText: "Hot"))
        case "Critical":
            return .present(SystemAlert(kind: .thermal, isCritical: true, title: "Your Mac is overheating",
                message: "macOS reports critical thermal pressure. Quit demanding apps and give your Mac room to cool down.",
                shortText: "Hot"))
        default: return .unknown
        }
    }

    private func storageCondition(_ snapshot: SystemSnapshot, active: Bool) -> Condition {
        guard let disk = snapshot.disk else { return .unknown }
        guard disk.available < (active ? Self.storageClearLimit : Self.storageLimit) else { return .absent }
        let free = MetricFormat.bytes(disk.available)
        return .present(SystemAlert(kind: .storage, isCritical: disk.available < Self.storageCriticalLimit,
            title: "Storage is almost full",
            message: "Only \(free) is free on your home volume. Apps and macOS updates can fail when the disk fills up.",
            shortText: "Disk \(free)"))
    }
}
