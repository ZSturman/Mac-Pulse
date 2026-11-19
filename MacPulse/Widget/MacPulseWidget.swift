import SwiftUI
import WidgetKit

struct PulseEntry: TimelineEntry {
    let date: Date
    let snapshot: SystemSnapshot

    // Used only for WidgetKit's placeholder/gallery, never in a real timeline.
    static var preview: PulseEntry {
        let date = Date()
        return PulseEntry(date: date, snapshot: SystemSnapshot(date: date,
            cpu: CPUReading(user: 14, system: 6),
            memory: MemoryReading(total: 16 * 1_073_741_824, app: 6 * 1_073_741_824,
                                  wired: 2 * 1_073_741_824, compressed: 1_073_741_824,
                                  cached: 3 * 1_073_741_824, pressure: .normal),
            swapUsed: 0, disk: nil, uptime: 0, thermal: "Nominal", warnings: []))
    }
}

struct PulseProvider: TimelineProvider {
    func placeholder(in context: Context) -> PulseEntry { .preview }

    func getSnapshot(in context: Context, completion: @escaping (PulseEntry) -> Void) {
        if context.isPreview { completion(.preview) } else { capture(completion) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PulseEntry>) -> Void) {
        capture { entry in
            // One observed sample. Never project today's load into fabricated future readings.
            completion(Timeline(entries: [entry], policy: .after(entry.date.addingTimeInterval(15 * 60))))
        }
    }

    private func capture(_ completion: @escaping (PulseEntry) -> Void) {
        let queue = DispatchQueue(label: "com.local.MacPulse.widget-sample", qos: .utility)
        queue.async {
            let sampler = SystemSampler()
            _ = sampler.sample(includeDisk: false)
            // CPU usage requires two counter readings. The queue waits without blocking WidgetKit.
            queue.asyncAfter(deadline: .now() + 0.5) {
                let snapshot = sampler.sample(includeDisk: false)
                completion(PulseEntry(date: snapshot.date, snapshot: snapshot))
            }
        }
    }
}

@main
struct MacPulseWidget: Widget {
    let kind = "MacPulseSnapshot"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PulseProvider()) { entry in
            PulseWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color(nsColor: .windowBackgroundColor) }
        }
        .configurationDisplayName("Mac Pulse")
        .description("A timestamped CPU and memory snapshot. Click to open the live dashboard.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct PulseWidgetView: View {
    let entry: PulseEntry
    @Environment(\.widgetFamily) private var family

    private var snapshot: SystemSnapshot { entry.snapshot }
    private var pressure: MemoryPressure { snapshot.memory?.pressure ?? .unknown }
    private var pressureColor: Color {
        switch pressure {
        case .normal: return .green
        case .warning: return .orange
        case .critical: return .red
        case .unknown: return .secondary
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 9 : 14) {
            HStack {
                Label("Mac Pulse", systemImage: "waveform.path.ecg").font(.caption.weight(.semibold))
                Spacer(minLength: 0)
                if family != .systemSmall {
                    Text("SNAPSHOT").font(.system(size: 8, weight: .semibold)).tracking(1).foregroundStyle(.secondary)
                }
            }

            if family == .systemSmall {
                smallMetric("CPU", value: snapshot.cpu?.total, color: .mint)
                smallMetric("Memory", value: snapshot.memory?.percent, color: .purple)
            } else {
                HStack(spacing: 24) {
                    metricGauge("CPU", value: snapshot.cpu?.total, color: .mint)
                    metricGauge("Memory", value: snapshot.memory?.percent, color: .purple)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Memory pressure").font(.system(size: 10)).foregroundStyle(.secondary)
                        Label(pressure.title, systemImage: pressure == .normal ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                            .font(.caption.weight(.medium)).foregroundStyle(pressureColor)
                        if let memory = snapshot.memory {
                            Text("\(MetricFormat.bytes(memory.used)) used")
                                .font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if family == .systemLarge {
                Divider()
                Text(snapshot.headline).font(.headline)
                Text(snapshot.explanation).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                widgetRow("Compressed", value: snapshot.memory.map { MetricFormat.bytes($0.compressed) } ?? "—")
                widgetRow("Swap used", value: snapshot.swapUsed.map(MetricFormat.bytes) ?? "—")
            }

            Spacer(minLength: 0)
            HStack(spacing: 3) {
                Image(systemName: "clock").accessibilityHidden(true)
                Text("Sampled")
                Text(snapshot.date, style: .time)
                Spacer(minLength: 0)
            }.font(.system(size: 9)).foregroundStyle(.secondary)
        }
        .widgetURL(URL(string: "macpulse://overview"))
    }

    private func smallMetric(_ title: String, value: Double?, color: Color) -> some View {
        VStack(spacing: 3) {
            HStack {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(MetricFormat.percent(value)).font(.system(.callout, design: .rounded).weight(.semibold)).monospacedDigit()
            }
            if let value { ProgressView(value: value, total: 100).tint(color) }
        }
    }

    private func metricGauge(_ title: String, value: Double?, color: Color) -> some View {
        VStack(spacing: 5) {
            if let value {
                Gauge(value: value, in: 0...100) { Text(title) } currentValueLabel: {
                    Text(MetricFormat.percent(value)).font(.system(size: 14, weight: .semibold, design: .rounded))
                }.gaugeStyle(.accessoryCircular).tint(color)
            } else {
                Text("—").font(.title2).frame(width: 58, height: 58)
            }
            Text(title).font(.system(size: 10)).foregroundStyle(.secondary)
        }.accessibilityElement(children: .combine)
    }

    private func widgetRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit()
        }.font(.caption)
    }
}

#Preview(as: .systemMedium) {
    MacPulseWidget()
} timeline: {
    PulseEntry.preview
}
