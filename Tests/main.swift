import Foundation
import Darwin

var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    checks += 1
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}
func close(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 0.001 }

let before = CPUCounters(user: 100, system: 20, idle: 200, nice: 0)
let after = CPUCounters(user: 130, system: 30, idle: 250, nice: 10)
let cpu = after.reading(since: before)!
check(close(cpu.total, 50), "aggregate CPU uses deltas, including nice time")
check(close(cpu.user, 40) && close(cpu.system, 10) && close(cpu.idle, 50), "CPU breakdown sums to 100")
check(before.reading(since: before) == nil, "zero interval has no invented CPU reading")
let wrapped = CPUCounters(user: 5, system: 0, idle: 6, nice: 0)
let wrapBefore = CPUCounters(user: UInt32.max - 4, system: 0, idle: 0, nice: 0)
check(close(wrapped.reading(since: wrapBefore)!.total, 62.5), "kernel tick rollover")

let memory = MemoryReading.fromPages(total: 1000, pageSize: 10, internalPages: 40,
    purgeable: 5, wired: 10, compressed: 5, external: 20, pressure: .normal)
check(memory.app == 350 && memory.wired == 100 && memory.compressed == 50, "page size and purgeable exclusion")
check(memory.used == 500 && memory.available == 500 && close(memory.percent, 50), "memory totals")
check(memory.cached == 250, "file cache remains separate from memory used")
let racing = MemoryReading.fromPages(total: 100, pageSize: 1, internalPages: 2,
    purgeable: 3, wired: 0, compressed: 0, external: 0, pressure: .unknown)
check(racing.app == 0, "non-atomic VM counters cannot underflow")
check(ProcessSampler.cpuPercent(current: 0, previous: 1, elapsed: 1) == nil, "process CPU reset rejected")
check(ProcessSampler.cpuPercent(current: 1, previous: 0, elapsed: 0) == nil, "zero process interval rejected")
check(close(ProcessSampler.cpuPercent(current: 4_000_000_000, previous: 0, elapsed: 2)!, 200), "multicore process may exceed 100%")
check(close(ProcessSampler.cpuPercent(current: 24_000_000, previous: 0, elapsed: 1,
    nanosecondsPerTick: 125.0 / 3)!, 100), "Apple silicon Mach timebase conversion")

func process(_ pid: Int32, started: UInt64 = 1, cpu: Double?, parent: Int32 = 1,
             app: ProcessApp? = nil) -> ProcessReading {
    ProcessReading(id: ProcessIdentity(pid: pid, started: started), name: "Process \(pid)",
                   cpu: cpu, memory: UInt64(pid), parentPID: parent, executablePath: nil, app: app)
}

let idleReadings = (2...7).map { process(Int32($0), cpu: 0) }
let busy = process(7, cpu: 80)
let busyReadings = Array(idleReadings.dropLast()) + [busy]
let initialRanking = ProcessRanking().updated(with: idleReadings, order: .cpu, at: 0)
check(initialRanking.rises.isEmpty, "initial rankings do not flash")
let ranked = initialRanking.updated(with: busyReadings, order: .cpu, at: 1)
check(ranked.readings.first?.id == busy.id && ranked.rises[busy.id]?.places == 5,
      "a CPU rise from outside the top five reports the full rank gain")
let steadyRanking = ranked.updated(with: busyReadings, order: .cpu, at: 2)
check(steadyRanking.rises[busy.id] == ranked.rises[busy.id], "steady rank does not restart the fade")
check(steadyRanking.updated(with: busyReadings, order: .cpu, at: 3).rises.isEmpty, "old rises expire")
let reused = process(7, started: 2, cpu: 80)
let reusedRanking = initialRanking.updated(with: Array(idleReadings.dropLast()) + [reused], order: .cpu, at: 1)
check(reusedRanking.rises[reused.id] != nil && reusedRanking.rises[reused.id]?.places == nil,
      "reused PIDs do not inherit a previous process rank")
let noCPU = ProcessRanking().updated(with: [process(2, cpu: nil)], order: .cpu, at: 0)
check(noCPU.updated(with: [process(2, cpu: 10)], order: .cpu, at: 1).rises.isEmpty,
      "first measurable CPU sample establishes the ranking baseline")
let initialMemory = ProcessRanking().updated(with: idleReadings, order: .memory, at: 0)
check(initialMemory.updated(with: busyReadings, order: .memory, at: 1).rises.isEmpty,
      "CPU activity by itself does not trigger a memory rise")

let app = ProcessApp(name: "Example", bundlePath: "/Applications/Example.app", source: .executable)
var processTree = [process(10, cpu: 1, app: app), process(11, cpu: 1, parent: 10),
                   process(12, cpu: 1, parent: 11), process(13, started: 0, cpu: 1, parent: 10)]
ProcessSampler.attributeApps(in: &processTree)
check(processTree[2].app?.name == app.name && processTree[2].app?.source == .ancestor
      && processTree[2].parentName == "Process 11", "app attribution walks through intermediate helpers")
check(processTree[0].app?.source == .executable && processTree[3].app == nil,
      "direct bundle attribution is preserved and a newer PID cannot be a process's parent")

func snapshot(pressure: MemoryPressure, cpu: Double) -> SystemSnapshot {
    SystemSnapshot(date: Date(), cpu: CPUReading(user: cpu, system: 0),
        memory: MemoryReading(total: 100, app: 90, wired: 0, compressed: 0, cached: 0, pressure: pressure),
        swapUsed: 0, disk: nil, uptime: 0, thermal: "Nominal", warnings: [])
}
check(snapshot(pressure: .normal, cpu: 5).headline.contains("room to breathe"), "high RAM alone is not an alarm")
check(snapshot(pressure: .warning, cpu: 95).headline.contains("Memory"), "memory pressure takes priority over CPU")
check(snapshot(pressure: .critical, cpu: 5).headline.contains("short on memory"), "critical pressure guidance")

func alertSnapshot(cpu: Double? = 5, pressure: MemoryPressure = .normal, thermal: String = "Nominal",
                   free: UInt64 = 100_000_000_000) -> SystemSnapshot {
    SystemSnapshot(date: Date(), cpu: cpu.map { CPUReading(user: $0, system: 0) },
        memory: MemoryReading(total: 100, app: 50, wired: 0, compressed: 0, cached: 0, pressure: pressure),
        swapUsed: 0, disk: DiskReading(total: 500_000_000_000, available: free), uptime: 0, thermal: thermal, warnings: [])
}
/// Feeds samples every `step` seconds from `start` through `end` and returns all announcements.
func feed(_ monitor: inout AlertMonitor, _ snapshot: SystemSnapshot, from start: Double, to end: Double,
          step: Double = 2) -> [SystemAlert] {
    stride(from: start, through: end, by: step).flatMap { monitor.update(with: snapshot, at: $0, cpuThreshold: 85) }
}
var calm = AlertMonitor()
check(feed(&calm, alertSnapshot(), from: 0, to: 120).isEmpty && calm.alerts.isEmpty, "a calm Mac raises no alerts")
var spike = AlertMonitor()
_ = feed(&spike, alertSnapshot(), from: 0, to: 50)
check(feed(&spike, alertSnapshot(cpu: 100), from: 52, to: 60).isEmpty, "a brief CPU spike is ignored")
var busyCPU = AlertMonitor()
check(feed(&busyCPU, alertSnapshot(cpu: 95), from: 0, to: 40).isEmpty, "CPU alerts wait for most of a minute")
let busyAnnounced = feed(&busyCPU, alertSnapshot(cpu: 95), from: 42, to: 120)
check(busyAnnounced.map(\.kind) == [.cpu] && busyCPU.alerts.first?.shortText == "CPU 95%",
      "sustained CPU raises one announcement and shows the live value")
_ = feed(&busyCPU, alertSnapshot(cpu: 80), from: 122, to: 200)
check(busyCPU.alerts.map(\.kind) == [.cpu], "CPU just under the threshold keeps an active alert (hysteresis)")
_ = feed(&busyCPU, alertSnapshot(cpu: 10), from: 202, to: 300)
check(busyCPU.alerts.isEmpty, "CPU alert clears once activity settles")
check(feed(&busyCPU, alertSnapshot(cpu: 95), from: 302, to: 420).isEmpty && busyCPU.alerts.map(\.kind) == [.cpu],
      "a recurring alert shows in the menu bar but does not re-notify within the cooldown")
var pressured = AlertMonitor()
check(feed(&pressured, alertSnapshot(pressure: .warning), from: 0, to: 20).isEmpty, "elevated pressure must persist")
check(feed(&pressured, alertSnapshot(pressure: .warning), from: 22, to: 40).map(\.kind) == [.memory],
      "persistent elevated pressure raises a memory alert")
check(feed(&pressured, alertSnapshot(pressure: .critical), from: 42, to: 44).first?.isCritical == true,
      "escalation to critical is announced despite the cooldown")
_ = feed(&pressured, alertSnapshot(pressure: .unknown), from: 46, to: 120)
check(pressured.alerts.map(\.kind) == [.memory], "an unavailable reading neither raises nor clears an alert")
_ = feed(&pressured, alertSnapshot(pressure: .normal), from: 122, to: 140)
check(!pressured.alerts.isEmpty, "alerts wait to settle before clearing")
_ = feed(&pressured, alertSnapshot(pressure: .normal), from: 142, to: 160)
check(pressured.alerts.isEmpty, "settled pressure clears the alert")
var hot = AlertMonitor()
check(hot.update(with: alertSnapshot(thermal: "Serious"), at: 0, cpuThreshold: 85).map(\.kind) == [.thermal],
      "serious thermal state alerts immediately")
var several = AlertMonitor()
_ = feed(&several, alertSnapshot(cpu: 99, pressure: .critical, thermal: "Critical", free: 1_000_000_000), from: 0, to: 60)
check(several.alerts.map(\.kind) == [.memory, .thermal, .cpu, .storage] && several.alerts.last?.isCritical == true,
      "alerts are ordered by priority and very low storage is critical")
several.reset()
check(several.alerts.isEmpty, "pausing clears stale alerts")
check(!MenuBarMode.alerts.isInserted(hasAlerts: false) && MenuBarMode.alerts.isInserted(hasAlerts: true)
      && MenuBarMode.always.isInserted(hasAlerts: false) && !MenuBarMode.never.isInserted(hasAlerts: true),
      "menu bar visibility follows the chosen mode")

// Read-only smoke checks on the real Mac. No process names or readings are persisted.
let system = SystemSampler()
let processes = ProcessSampler()
let first = system.sample()
check(first.cpu == nil, "initial CPU sample waits for a baseline")
_ = processes.sample()
Thread.sleep(forTimeInterval: 0.3)
let live = system.sample()
let liveProcesses = processes.sample()
check(live.cpu != nil && (0...100).contains(live.cpu!.total), "live CPU counters are readable")
check(live.memory != nil && live.memory!.used <= live.memory!.total && live.memory!.total > 0, "live VM statistics are readable")
check(live.swapUsed != nil, "swap sysctl is readable")
check(live.disk != nil && live.disk!.total > 0, "home volume capacity is readable")
check(!liveProcesses.enumerationFailed, "process enumeration succeeds")
check(liveProcesses.readings.contains { $0.pid == getpid() && $0.cpu != nil }, "own process CPU and memory are readable")
check(liveProcesses.readings.first { $0.pid == getpid() }?.executablePath?.hasSuffix("/CoreChecks") == true,
      "own executable path is readable")

// Compare against an independent OS CPU clock after a short, bounded amount of real work.
func cpuSeconds() -> Double {
    var usage = rusage()
    getrusage(RUSAGE_SELF, &usage)
    return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec)
        + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
}
let spinSampler = ProcessSampler()
_ = spinSampler.sample()
let wallStart = ProcessInfo.processInfo.systemUptime
let cpuStart = cpuSeconds()
var spinValue = 0.0
while ProcessInfo.processInfo.systemUptime - wallStart < 0.2 { spinValue += sin(spinValue + 0.1) }
let cpuElapsed = cpuSeconds() - cpuStart
let wallElapsed = ProcessInfo.processInfo.systemUptime - wallStart
let measured = spinSampler.sample().readings.first { $0.pid == getpid() }?.cpu ?? 0
let expected = cpuElapsed / wallElapsed * 100
check(expected > 10 && measured > expected * 0.5 && measured < expected * 1.5,
      "process CPU agrees with getrusage across the native Mach timebase")
check(spinValue.isFinite, "bounded live CPU work completed")
system.reset()
check(system.sample().cpu == nil, "resume resets the CPU baseline")
print("PASS: \(checks) core checks (deterministic metric math + read-only live sampling).")
