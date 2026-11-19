import AppKit
import ServiceManagement
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) { AlertNotifier.shared.start() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

@main
struct MacPulseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var monitor = MonitorStore()
    @AppStorage("menuBarMode") private var menuBarMode = MenuBarMode.alerts

    var body: some Scene {
        Window("Mac Pulse", id: "dashboard") {
            ContentView(monitor: monitor)
                .frame(minWidth: 850, minHeight: 650)
        }
        .defaultSize(width: 1160, height: 850)
        .commands {
            CommandGroup(after: .appInfo) {
                Button(monitor.isPaused ? "Resume Monitoring" : "Pause Monitoring") { monitor.togglePause() }
                    .keyboardShortcut("p", modifiers: [.command, .shift])
                Button("Clear Graph History") { monitor.clearHistory() }
            }
        }

        // The setter is ignored: visibility follows the Settings choice and current alerts.
        MenuBarExtra(isInserted: Binding(get: { menuBarMode.isInserted(hasAlerts: !monitor.alerts.isEmpty) },
                                         set: { _ in })) {
            MenuPanel(monitor: monitor)
        } label: {
            if let alert = monitor.alerts.first {
                Image(systemName: "exclamationmark.triangle.fill")
                Text(monitor.alerts.count > 1 ? "\(alert.shortText) +\(monitor.alerts.count - 1)" : alert.shortText)
                    .monospacedDigit()
                    .accessibilityLabel("Mac Pulse: \(monitor.alerts.map(\.title).joined(separator: ", "))")
            } else {
                Image(systemName: "waveform.path.ecg")
                Text(monitor.isPaused ? "Paused" : "CPU \(MetricFormat.percent(monitor.snapshot?.cpu?.total))")
                    .monospacedDigit()
                    .accessibilityLabel(monitor.isPaused ? "Mac Pulse paused" : "Mac Pulse CPU \(MetricFormat.percent(monitor.snapshot?.cpu?.total))")
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(monitor: monitor, menuBarMode: $menuBarMode)
        }
    }
}

struct SettingsView: View {
    @ObservedObject var monitor: MonitorStore
    @Binding var menuBarMode: MenuBarMode
    @AppStorage(AlertNotifier.enabledKey) private var notify = true
    @AppStorage("cpuAlertThreshold") private var cpuThreshold = 85.0
    @State private var notificationsDenied = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section {
                Picker("Update live readings every", selection: Binding(get: { monitor.interval }, set: monitor.setInterval)) {
                    Text("1 second").tag(1.0)
                    Text("2 seconds (recommended)").tag(2.0)
                    Text("5 seconds").tag(5.0)
                }
                Picker("Show in the menu bar", selection: $menuBarMode) {
                    ForEach(MenuBarMode.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Open at login", isOn: Binding(get: { launchAtLogin }, set: setLaunchAtLogin))
                if let loginError {
                    Text(loginError).font(.callout).foregroundStyle(.orange)
                }
            }
            Section("Alerts") {
                Toggle("Notify me when something needs attention", isOn: $notify)
                    .onChange(of: notify) { _, enabled in if enabled { AlertNotifier.shared.requestAuthorization() } }
                if notify && notificationsDenied {
                    HStack {
                        Text("Notifications are turned off for Mac Pulse in System Settings.")
                            .font(.callout).foregroundStyle(.orange)
                        Spacer()
                        Button("Open") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                }
                Picker("Alert when CPU averages", selection: $cpuThreshold) {
                    Text("75% for a minute").tag(75.0)
                    Text("85% for a minute").tag(85.0)
                    Text("95% for a minute").tag(95.0)
                }
                Text("Mac Pulse also alerts on elevated memory pressure lasting 30 seconds, serious or critical thermal state (macOS reports a category, not a temperature), and less than 10 GB of free storage. Each kind notifies at most once every 30 minutes unless it becomes critical.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section {
                Text("Monitoring and alerts run only while Mac Pulse is open, including when its window is closed. Use Mac Pulse → Quit Mac Pulse to stop it.")
                    .font(.callout).foregroundStyle(.secondary)
                Text("Desktop widgets take their own snapshots. macOS decides when they refresh; these settings change the live app only.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(12)
        .frame(width: 520)
        .task { notificationsDenied = await AlertNotifier.shared.authorizationDenied() }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = SMAppService.mainApp.status == .requiresApproval
                ? "Allow Mac Pulse in System Settings → General → Login Items." : nil
        } catch {
            loginError = "Could not change the login item: \(error.localizedDescription)"
        }
        launchAtLogin = SMAppService.mainApp.status != .notRegistered
    }
}

struct MenuPanel: View {
    @ObservedObject var monitor: MonitorStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label("Mac Pulse", systemImage: "waveform.path.ecg").font(.headline)
                Spacer()
                Text(monitor.isPaused ? "PAUSED" : "LIVE")
                    .font(.caption2.weight(.semibold)).foregroundStyle(monitor.isPaused ? .orange : .secondary)
            }
            HStack(spacing: 28) {
                menuMetric("CPU", value: MetricFormat.percent(monitor.snapshot?.cpu?.total), color: .mint)
                menuMetric("Memory", value: MetricFormat.percent(monitor.snapshot?.memory?.percent), color: .purple)
            }
            if !monitor.alerts.isEmpty {
                alertList
            }
            if let snapshot = monitor.snapshot {
                if monitor.alerts.isEmpty {
                    Text(snapshot.headline).font(.subheadline.weight(.medium))
                }
                Label("Memory pressure: \(snapshot.memory?.pressure.title ?? "Unavailable")", systemImage: "memorychip")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Sampled \(snapshot.date.formatted(date: .omitted, time: .standard))")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Divider()
            if monitor.alerts.contains(where: { $0.kind.involvesProcesses }) {
                Button("Investigate in Processes") { open(.processes) }
                    .buttonStyle(.borderedProminent).frame(maxWidth: .infinity)
                Button("Open Dashboard") { open(.overview) }.frame(maxWidth: .infinity)
            } else {
                Button("Open Dashboard") { open(.overview) }
                    .buttonStyle(.borderedProminent).frame(maxWidth: .infinity)
            }
            HStack {
                Button(monitor.isPaused ? "Resume" : "Pause") { monitor.togglePause() }
                Spacer()
                Button("Quit Mac Pulse") { NSApp.terminate(nil) }
            }.font(.caption)
        }
        .padding(20)
        .frame(width: 310)
    }

    private func open(_ page: MonitorPage) {
        monitor.requestedPage = page
        openWindow(id: "dashboard")
        NSApp.activate(ignoringOtherApps: true)
    }

    private var alertList: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(monitor.alerts) { alert in
                Label {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(alert.title).font(.subheadline.weight(.semibold))
                        Text(alert.message).font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } icon: {
                    Image(systemName: alert.kind.icon).foregroundStyle(alert.isCritical ? .red : .orange)
                }
            }
            if let order = leaderOrder {
                let leaders = monitor.ranking(for: order).readings.prefix(3)
                if !leaders.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(order == .cpu ? "Using the most CPU" : "Using the most memory")
                            .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                        ForEach(leaders) { process in
                            HStack {
                                Text(process.app?.name ?? process.displayName).lineLimit(1)
                                Spacer()
                                Text(order == .cpu ? MetricFormat.percent(process.cpu) : MetricFormat.bytes(process.memory))
                                    .monospacedDigit().foregroundStyle(.secondary)
                            }.font(.caption)
                        }
                    }
                }
            }
        }
    }

    /// Memory alerts list memory leaders; CPU and thermal alerts list CPU leaders.
    private var leaderOrder: ProcessOrder? {
        guard let alert = monitor.alerts.first(where: { $0.kind.involvesProcesses }) else { return nil }
        return alert.kind == .memory ? .memory : .cpu
    }

    private func menuMetric(_ title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(size: 29, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
