import AppKit
import Combine
import Foundation

@MainActor
final class MonitorStore: ObservableObject {
    @Published private(set) var snapshot: SystemSnapshot?
    @Published private(set) var history: [HistoryPoint] = []
    @Published private var processRankings: [ProcessOrder: ProcessRanking] = [:]
    @Published private(set) var inaccessibleProcesses = 0
    @Published private(set) var processEnumerationFailed = false
    @Published private(set) var isPaused = false
    @Published private(set) var interval: Double
    @Published private(set) var alerts: [SystemAlert] = []
    /// A page the dashboard should show next, requested from the menu bar panel.
    @Published var requestedPage: MonitorPage?

    private let queue = DispatchQueue(label: "com.local.MacPulse.sampling", qos: .utility)
    private let system = SystemSampler()
    private let processSampler = ProcessSampler()
    private var timer: DispatchSourceTimer?
    private var generation = 0
    private var wakeObserver: NSObjectProtocol?
    // History keeps accumulating while hidden; `history` is only republished for a visible dashboard.
    private var recentHistory: [HistoryPoint] = []
    // Starts hidden: the dashboard reports itself once its window is actually on screen.
    private var isDashboardVisible = false
    private var alertMonitor = AlertMonitor()
    // Whether the running timer was started with process enumeration.
    private var samplingIncludesProcesses = false

    init() {
        let saved = UserDefaults.standard.double(forKey: "sampleInterval")
        interval = [1.0, 2.0, 5.0].contains(saved) ? saved : 2
        startSampling()
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.startSampling() }
        }
    }

    deinit {
        timer?.cancel()
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
    }

    func setInterval(_ seconds: Double) {
        guard [1.0, 2.0, 5.0].contains(seconds), seconds != interval else { return }
        interval = seconds
        UserDefaults.standard.set(seconds, forKey: "sampleInterval")
        startSampling()
    }

    func togglePause() {
        isPaused.toggle()
        if isPaused {
            // Paused readings cannot confirm a condition is still present.
            alertMonitor.reset()
            alerts = []
        }
        startSampling()
    }

    func clearHistory() {
        recentHistory.removeAll()
        history.removeAll()
    }

    func ranking(for order: ProcessOrder) -> ProcessRanking {
        processRankings[order] ?? ProcessRanking()
    }

    /// Called when the dashboard window becomes visible, or is closed, minimized, covered, or moved off screen.
    /// While hidden, the store skips process enumeration and stops republishing dashboard state,
    /// so the monitor does not spend CPU redrawing a window nobody can see.
    func setDashboardVisible(_ visible: Bool) {
        guard visible != isDashboardVisible else { return }
        isDashboardVisible = visible
        if visible {
            history = recentHistory
        } else if !alertsNeedProcesses {
            // Stale rankings would otherwise produce spurious rank-rise highlights on return.
            processRankings = [:]
        }
        startSampling(resetSystem: false)
    }

    private var menuBarShowsReadings: Bool {
        let mode = UserDefaults.standard.string(forKey: "menuBarMode").flatMap(MenuBarMode.init) ?? .alerts
        return mode.isInserted(hasAlerts: !alerts.isEmpty)
    }

    private var cpuAlertThreshold: Double {
        let saved = UserDefaults.standard.double(forKey: "cpuAlertThreshold")
        return saved > 0 ? saved : 85
    }

    /// While CPU, memory, or thermal alerts are active, process readings show what is responsible.
    private var alertsNeedProcesses: Bool { alerts.contains { $0.kind.involvesProcesses } }

    private func startSampling(resetSystem: Bool = true) {
        generation += 1
        let currentGeneration = generation
        timer?.cancel()
        timer = nil
        guard !isPaused else { return }
        let system = system
        let processSampler = processSampler
        let includeProcesses = isDashboardVisible || alertsNeedProcesses
        samplingIncludesProcesses = includeProcesses
        queue.async {
            if resetSystem { system.reset() }
            processSampler.reset()
        }
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: .now(), repeating: interval, leeway: .milliseconds(150))
        source.setEventHandler { [weak self] in
            let snapshot = system.sample()
            // Process readings only feed the dashboard and active alerts.
            let processes = includeProcesses ? processSampler.sample() : nil
            let sampleTime = ProcessInfo.processInfo.systemUptime
            Task { @MainActor [weak self] in
                guard let self, self.generation == currentGeneration, !self.isPaused else { return }
                self.recentHistory.append(HistoryPoint(date: snapshot.date, cpu: snapshot.cpu?.total,
                                                       memory: snapshot.memory?.percent))
                let cutoff = snapshot.date.addingTimeInterval(-300)
                self.recentHistory.removeAll { $0.date < cutoff }
                if self.recentHistory.count > 301 { self.recentHistory.removeFirst(self.recentHistory.count - 301) }
                let announced = self.alertMonitor.update(with: snapshot, at: sampleTime, cpuThreshold: self.cpuAlertThreshold)
                if self.alerts != self.alertMonitor.alerts { self.alerts = self.alertMonitor.alerts }
                AlertNotifier.shared.post(announced)
                if self.isDashboardVisible || self.menuBarShowsReadings { self.snapshot = snapshot }
                if let processes {
                    self.processRankings = Dictionary(uniqueKeysWithValues: ProcessOrder.allCases.map { order in
                        (order, self.ranking(for: order).updated(with: processes.readings, order: order, at: sampleTime))
                    })
                    self.inaccessibleProcesses = processes.inaccessible
                    self.processEnumerationFailed = processes.enumerationFailed
                }
                if self.isDashboardVisible { self.history = self.recentHistory }
                let needsProcesses = self.isDashboardVisible || self.alertsNeedProcesses
                if needsProcesses != self.samplingIncludesProcesses {
                    if !needsProcesses { self.processRankings = [:] }
                    self.startSampling(resetSystem: false)
                }
            }
        }
        timer = source
        source.resume()
    }
}
