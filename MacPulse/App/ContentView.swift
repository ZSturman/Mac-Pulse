import AppKit
import SwiftUI

enum MonitorPage: String, CaseIterable, Identifiable {
    case overview = "Overview", processes = "Processes", guide = "How to read your Mac"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .processes: return "list.bullet.rectangle"
        case .guide: return "book.closed"
        }
    }
}

struct ContentView: View {
    @ObservedObject var monitor: MonitorStore
    @State private var page: MonitorPage? = .overview
    @State private var selectedProcess: ProcessReading?
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.title2.weight(.medium)).foregroundStyle(.mint)
                        .frame(width: 36, height: 36)
                        .background(.mint.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Mac Pulse").font(.headline)
                        Text("Know your Mac.").font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(18).padding(.top, 12)
                List(MonitorPage.allCases, selection: $page) { item in
                    Label(item.rawValue, systemImage: item.icon).tag(item)
                        .padding(.vertical, 6)
                }
                .listStyle(.sidebar)
                Spacer(minLength: 12)
                VStack(alignment: .leading, spacing: 8) {
                    Label("On this Mac", systemImage: "desktopcomputer").font(.caption.weight(.medium))
                    Text("\(ProcessInfo.processInfo.processorCount) logical cores · \(MetricFormat.bytes(ProcessInfo.processInfo.physicalMemory)) RAM")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("Private. Local. Read-only.").font(.caption2).foregroundStyle(.tertiary)
                }.padding(18)
            }
            .navigationSplitViewColumnWidth(min: 205, ideal: 215, max: 260)
        } detail: {
            Group {
                switch page ?? .overview {
                case .overview:
                    DashboardView(monitor: monitor, showProcesses: { page = .processes },
                                  showDetails: { selectedProcess = $0 })
                case .processes:
                    ProcessesView(monitor: monitor, showDetails: { selectedProcess = $0 })
                case .guide: GuideView()
                }
            }
            .navigationTitle((page ?? .overview).rawValue)
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    if monitor.isPaused, let date = monitor.snapshot?.date {
                        Text("Paused at \(date.formatted(date: .omitted, time: .shortened))")
                            .font(.caption).foregroundStyle(.orange)
                    } else {
                        Label("Live · \(Int(monitor.interval))s", systemImage: "circle.fill")
                            .labelStyle(.titleAndIcon)
                            .font(.caption).foregroundStyle(.secondary)
                            .help("Live readings refresh every \(Int(monitor.interval)) seconds")
                    }
                    Button { monitor.togglePause() } label: {
                        Label(monitor.isPaused ? "Resume Monitoring" : "Pause Monitoring",
                              systemImage: monitor.isPaused ? "play.fill" : "pause.fill")
                    }
                    .help(monitor.isPaused ? "Resume monitoring" : "Pause monitoring")
                    SettingsLink { Image(systemName: "gearshape") }.help("Settings")
                }
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .tint(.mint)
        .sheet(item: $selectedProcess) { ProcessDetailsView(process: $0) }
        .background(WindowVisibilityObserver { monitor.setDashboardVisible($0) })
        .onAppear(perform: showRequestedPage)
        .onChange(of: monitor.requestedPage) { showRequestedPage() }
        .onOpenURL { url in
            guard url.scheme == "macpulse" else { return }
            page = url.host == "processes" ? .processes : .overview
            openWindow(id: "dashboard")
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

extension ContentView {
    private func showRequestedPage() {
        guard let requested = monitor.requestedPage else { return }
        page = requested
        monitor.requestedPage = nil
    }
}

/// Reports whether the hosting window is on screen: not closed, minimized, fully covered, or on another Space.
struct WindowVisibilityObserver: NSViewRepresentable {
    let onChange: (Bool) -> Void

    func makeNSView(context: Context) -> ObserverView { ObserverView(onChange: onChange) }
    func updateNSView(_ view: ObserverView, context: Context) { view.onChange = onChange }

    final class ObserverView: NSView {
        var onChange: (Bool) -> Void
        private var observers: [NSObjectProtocol] = []

        init(onChange: @escaping (Bool) -> Void) {
            self.onChange = onChange
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { nil }

        deinit { observers.forEach(NotificationCenter.default.removeObserver) }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            guard let window else {
                onChange(false)
                return
            }
            observers = [NSWindow.didChangeOcclusionStateNotification, NSWindow.willCloseNotification].map { name in
                NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] note in
                    let closing = note.name == NSWindow.willCloseNotification
                    MainActor.assumeIsolated { self?.report(closing: closing) }
                }
            }
            report(closing: false)
        }

        private func report(closing: Bool) {
            guard let window else { return }
            onChange(!closing && window.occlusionState.contains(.visible))
        }
    }
}
