import SwiftUI

struct ProcessesView: View {
    @ObservedObject var monitor: MonitorStore
    var showDetails: (ProcessReading) -> Void
    @State private var search = ""
    @State private var order: ProcessOrder = .cpu

    var body: some View {
        let ranking = monitor.ranking(for: order)
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = ranking.readings.enumerated().filter { _, process in
            query.isEmpty || process.displayName.localizedCaseInsensitiveContains(query)
                || process.app?.name.localizedCaseInsensitiveContains(query) == true || String(process.pid).contains(query)
        }

        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Process activity").font(.system(size: 26, weight: .semibold, design: .rounded))
                    Text("Click a process to see its app, parent, and executable.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Picker("Sort by", selection: $order) {
                    ForEach(ProcessOrder.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).labelsHidden().frame(width: 170)
            }
            HStack(spacing: 8) {
                TextField("Search by process, app, or PID", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Search processes")
                if !search.isEmpty {
                    Button("Clear search", systemImage: "xmark.circle.fill") { search = "" }
                        .labelStyle(.iconOnly).buttonStyle(.plain).foregroundStyle(.secondary)
                        .help("Clear search")
                }
            }
            HStack {
                Text(query.isEmpty ? "\(ranking.readings.count) processes" : "\(filtered.count) of \(ranking.readings.count) processes")
                Spacer()
                Text("\(monitor.inaccessibleProcesses) inaccessible or exited")
            }.font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Text("RANK").frame(width: 36, alignment: .trailing)
                    .help("Rank across all readable processes sorted by \(order.rawValue)")
                Text("PROCESS").frame(maxWidth: .infinity, alignment: .leading)
                Text("PID").frame(width: 65, alignment: .trailing)
                Text("CPU").frame(width: 80, alignment: .trailing)
                Text("MEMORY").frame(width: 100, alignment: .trailing)
                Color.clear.frame(width: 16, height: 1).accessibilityHidden(true)
            }.font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary).padding(.horizontal, 16)
            ScrollView {
                LazyVStack(spacing: 0) {
                    if filtered.isEmpty {
                        ContentUnavailableView(query.isEmpty ? "No process readings" : "No matches",
                                               systemImage: "list.bullet.rectangle",
                                               description: Text(query.isEmpty ? "Waiting for accessible process information." : "Try another process name, app name, or PID."))
                    }
                    ForEach(filtered, id: \.element.id) { index, process in
                        ProcessRow(process: process, rank: index + 1, showPID: true, rise: ranking.rises[process.id]) {
                            showDetails(process)
                        }
                        Divider().padding(.horizontal, 16)
                    }
                }
            }
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 5) {
                if monitor.processEnumerationFailed {
                    Text("macOS did not return the process list.").foregroundStyle(.orange)
                }
                Text("100% CPU equals one logical core; multithreaded processes can exceed 100%. A dash means a baseline is still needed.")
                Text("Some protected processes are inaccessible. Resident memory can include shared pages, so these rows do not add up to system memory used.")
            }.font(.caption).foregroundStyle(.secondary)
        }.padding(26)
    }
}

struct ProcessRows: View {
    let ranking: ProcessRanking
    let showDetails: (ProcessReading) -> Void

    var body: some View {
        let readings = Array(ranking.readings.prefix(ProcessRanking.highlightedCount))
        VStack(spacing: 0) {
            if readings.isEmpty {
                Text("Waiting for process readings…").font(.callout).foregroundStyle(.secondary).padding(.vertical, 24)
            }
            ForEach(Array(readings.enumerated()), id: \.element.id) { index, process in
                ProcessRow(process: process, rank: index + 1, showPID: false, rise: ranking.rises[process.id]) {
                    showDetails(process)
                }
                if index < readings.count - 1 { Divider() }
            }
        }
    }
}

struct ProcessRow: View {
    let process: ProcessReading
    let rank: Int
    let showPID: Bool
    let rise: ProcessRankRise?
    let showDetails: () -> Void
    @State private var isHovered = false
    @State private var showsRise = false
    @State private var riseOpacity: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: showDetails) {
            HStack(spacing: 12) {
                Text(rank.formatted(.number.grouping(.never)))
                    .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    .frame(width: showPID ? 36 : 20, alignment: .trailing)
                    .accessibilityLabel("Rank \(rank)")
                VStack(alignment: .leading, spacing: 2) {
                    Text(process.displayName).lineLimit(1)
                    if let app = process.app, app.name.localizedCaseInsensitiveCompare(process.displayName) != .orderedSame {
                        Text(app.name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                if let rise, showsRise {
                    Label(rise.places.map { "Up \($0)" } ?? "New in top 5", systemImage: "arrow.up")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(.mint.opacity(0.25), in: Capsule())
                        .opacity(riseOpacity)
                }
                if showPID { Text(String(process.pid)).foregroundStyle(.secondary).frame(width: 65, alignment: .trailing) }
                Text(process.cpu.map { String(format: "%.1f%%", $0) } ?? "—")
                    .frame(width: 80, alignment: .trailing)
                Text(MetricFormat.bytes(process.memory)).foregroundStyle(.secondary).frame(width: 100, alignment: .trailing)
                Image(systemName: "info.circle")
                    .foregroundStyle(isHovered ? .primary : .secondary).frame(width: 16)
                    .accessibilityHidden(true)
            }
            .font(.callout).monospacedDigit()
            .padding(.horizontal, showPID ? 16 : 8)
            .padding(.vertical, showPID ? 10 : 8)
            .background(.mint.opacity(0.22 * riseOpacity), in: RoundedRectangle(cornerRadius: 8))
            .background(.primary.opacity(isHovered ? 0.06 : 0), in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("Show details for \(process.displayName)")
        .task(id: rise) {
            let remaining = rise.map { ProcessRankRise.duration - (ProcessInfo.processInfo.systemUptime - $0.time) } ?? 0
            guard remaining > 0 else {
                showsRise = false
                riseOpacity = 0
                return
            }
            // Keep the fade short: an animated fade redraws every frame, and rank changes arrive on most samples.
            let fade = 0.3
            showsRise = true
            riseOpacity = reduceMotion ? 1 : min(1, remaining / fade)
            let hold = reduceMotion ? remaining : max(0, remaining - fade)
            if hold > 0 {
                try? await Task.sleep(for: .seconds(hold))
            }
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : .linear(duration: min(fade, remaining))) {
                riseOpacity = 0
            }
            if !reduceMotion {
                try? await Task.sleep(for: .seconds(min(fade, remaining)))
            }
            guard !Task.isCancelled else { return }
            showsRise = false
        }
    }
}

struct ProcessDetailsView: View {
    let process: ProcessReading
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(process.displayName).font(.title2.weight(.semibold)).textSelection(.enabled)
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow(alignment: .top) {
                    Text("App").foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 3) {
                        if let app = process.app {
                            Text(app.name).fontWeight(.medium).textSelection(.enabled)
                            Text(app.source.rawValue).font(.caption).foregroundStyle(.secondary)
                            Text(app.bundlePath).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        } else {
                            Text("No app identified")
                        }
                    }
                }
                GridRow {
                    Text("PID").foregroundStyle(.secondary)
                    Text(String(process.pid)).monospacedDigit().textSelection(.enabled)
                }
                GridRow {
                    Text("Parent").foregroundStyle(.secondary)
                    Text(parent).textSelection(.enabled)
                }
                GridRow(alignment: .top) {
                    Text("Executable").foregroundStyle(.secondary)
                    Text(process.executablePath ?? "Unavailable")
                        .font(.callout.monospaced()).textSelection(.enabled)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(width: 480, alignment: .leading)
    }

    private var parent: String {
        if let name = process.parentName { return "\(name) (PID \(process.parentPID))" }
        return process.parentPID > 0 ? "PID \(process.parentPID)" : "Unavailable"
    }
}
