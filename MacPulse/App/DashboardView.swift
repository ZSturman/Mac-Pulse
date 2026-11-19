import SwiftUI

struct DashboardView: View {
    @ObservedObject var monitor: MonitorStore
    var showProcesses: () -> Void
    var showDetails: (ProcessReading) -> Void
    @State private var order: ProcessOrder = .cpu

    private var snapshot: SystemSnapshot? { monitor.snapshot }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("YOUR MAC, AT A GLANCE")
                        .font(.system(size: 10, weight: .semibold)).tracking(2).foregroundStyle(.secondary)
                    Text(snapshot?.headline ?? "Getting to know your Mac.")
                        .font(.system(size: 27, weight: .semibold, design: .rounded))
                    Text(snapshot?.explanation ?? "Your first live readings will appear in a moment.")
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }.padding(.vertical, 6)

                if let warnings = snapshot?.warnings, !warnings.isEmpty {
                    Label(warnings.joined(separator: " "), systemImage: "exclamationmark.triangle")
                        .font(.callout).foregroundStyle(.orange)
                }

                HStack(alignment: .top, spacing: 18) {
                    cpuCard
                    memoryCard
                }

                HStack(alignment: .top, spacing: 18) {
                    systemCard("Swap used", icon: "arrow.left.arrow.right", value: snapshot?.swapUsed.map(MetricFormat.bytes) ?? "—",
                               detail: "Disk space used as extra memory")
                    systemCard("Storage available", icon: "internaldrive", value: snapshot?.disk.map { MetricFormat.bytes($0.available) } ?? "—",
                               detail: "On your home volume")
                    systemCard("System uptime", icon: "clock", value: snapshot.map { MetricFormat.uptime($0.uptime) } ?? "—",
                               detail: "Thermal state: \(snapshot?.thermal ?? "—")")
                }

                PulseCard {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("What’s using your Mac?").font(.headline)
                                Text("Individual processes · sorted by \(order.rawValue)").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Picker("Sort processes by", selection: $order) {
                                ForEach(ProcessOrder.allCases) { Text($0.rawValue).tag($0) }
                            }.pickerStyle(.segmented).labelsHidden().frame(width: 150)
                        }
                        ProcessRows(ranking: monitor.ranking(for: order), showDetails: showDetails)
                        HStack {
                            Text("CPU: 100% = one core. Memory: resident RAM.")
                                .font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button("All processes", systemImage: "arrow.right", action: showProcesses)
                                .buttonStyle(.plain).font(.callout).foregroundStyle(.mint)
                        }
                        if monitor.processEnumerationFailed {
                            Text("Process information is unavailable. System readings remain independent.")
                                .font(.caption).foregroundStyle(.orange)
                        }
                    }
                }

                HStack(spacing: 5) {
                    Image(systemName: "lock.shield")
                    Text("Readings stay on your Mac. History covers the last 5 minutes while monitoring runs.")
                }.font(.caption2).foregroundStyle(.secondary).padding(.bottom, 4)
            }
            .padding(26)
            .frame(maxWidth: 1300)
            .frame(maxWidth: .infinity)
        }
    }

    private var cpuCard: some View {
        PulseCard {
            VStack(alignment: .leading, spacing: 15) {
                HStack {
                    Label("CPU", systemImage: "cpu").font(.headline)
                    Spacer()
                    Text("\(ProcessInfo.processInfo.processorCount) cores").font(.caption).foregroundStyle(.secondary)
                }.frame(height: 28)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(MetricFormat.percent(snapshot?.cpu?.total))
                        .font(.system(size: 43, weight: .medium, design: .rounded)).monospacedDigit()
                    Text("in use").font(.callout).foregroundStyle(.secondary)
                }.frame(height: 52, alignment: .leading)
                HistoryChart(history: monitor.history, memory: false, end: snapshot?.date ?? Date(), color: .mint)
                chartFooter
                HStack(spacing: 14) {
                    MetricLegend(name: "User", value: MetricFormat.percent(snapshot?.cpu?.user), color: .mint)
                    MetricLegend(name: "System", value: MetricFormat.percent(snapshot?.cpu?.system), color: .blue)
                }
                Divider()
                KeyValue(label: "Headroom", value: MetricFormat.percent(snapshot?.cpu?.idle))
            }
        }
    }

    private var memoryCard: some View {
        PulseCard {
            VStack(alignment: .leading, spacing: 15) {
                HStack {
                    Label("Memory", systemImage: "memorychip").font(.headline)
                    Spacer()
                    PressureBadge(pressure: snapshot?.memory?.pressure ?? .unknown)
                }.frame(height: 28)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(snapshot?.memory.map { MetricFormat.bytes($0.used) } ?? "—")
                        .font(.system(size: 36, weight: .medium, design: .rounded)).monospacedDigit().minimumScaleFactor(0.7)
                    Text("/ \(MetricFormat.bytes(ProcessInfo.processInfo.physicalMemory))")
                        .font(.callout).foregroundStyle(.secondary)
                }.frame(height: 52, alignment: .leading)
                HistoryChart(history: monitor.history, memory: true, end: snapshot?.date ?? Date(), color: .purple)
                chartFooter
                HStack(spacing: 12) {
                    MetricLegend(name: "App", value: snapshot?.memory.map { MetricFormat.bytes($0.app) } ?? "—", color: .purple)
                    MetricLegend(name: "Wired", value: snapshot?.memory.map { MetricFormat.bytes($0.wired) } ?? "—", color: .blue)
                }
                Divider()
                KeyValue(label: "Compressed", value: snapshot?.memory.map { MetricFormat.bytes($0.compressed) } ?? "—")
            }
        }
    }

    private var chartFooter: some View {
        HStack {
            Text("5 min ago")
            Spacer()
            Text(monitor.isPaused ? "Paused" : "Now")
        }.font(.system(size: 10)).foregroundStyle(.tertiary)
    }

    private func systemCard(_ title: String, icon: String, value: String, detail: String) -> some View {
        PulseCard {
            VStack(alignment: .leading, spacing: 8) {
                Label(title, systemImage: icon).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.system(size: 22, weight: .medium, design: .rounded)).monospacedDigit()
                Text(detail).font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
