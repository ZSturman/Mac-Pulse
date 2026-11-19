import SwiftUI
import Charts

extension MemoryPressure {
    var color: Color {
        switch self {
        case .normal: return .green
        case .warning: return .orange
        case .critical: return .red
        case .unknown: return .secondary
        }
    }
}

struct PulseCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.primary.opacity(0.07)))
    }
}

struct PressureBadge: View {
    let pressure: MemoryPressure
    var body: some View {
        Label(pressure.title, systemImage: pressure == .normal ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
            .font(.caption.weight(.medium))
            .foregroundStyle(pressure.color)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(pressure.color.opacity(0.1), in: Capsule())
            .accessibilityLabel("Memory pressure \(pressure.title)")
    }
}

struct MetricLegend: View {
    let name: String
    let value: String
    let color: Color
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 6, height: 6).accessibilityHidden(true)
            Text(name).foregroundStyle(.secondary)
            Text(value).monospacedDigit()
        }.font(.caption)
    }
}

struct HistoryChart: View {
    let history: [HistoryPoint]
    let memory: Bool
    let end: Date
    let color: Color

    var body: some View {
        Chart(history) { point in
            if let value = memory ? point.memory : point.cpu {
                AreaMark(x: .value("Time", point.date), yStart: .value("Baseline", 0), yEnd: .value("Usage", value))
                    .foregroundStyle(LinearGradient(colors: [color.opacity(0.23), color.opacity(0.01)], startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("Time", point.date), y: .value("Usage", value))
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .foregroundStyle(color)
            }
        }
        .chartYScale(domain: 0...100)
        .chartXScale(domain: end.addingTimeInterval(-300)...end)
        .chartYAxis {
            AxisMarks(position: .trailing, values: [0, 50, 100]) { value in
                AxisGridLine().foregroundStyle(.primary.opacity(0.06))
                AxisValueLabel { if let n = value.as(Int.self) { Text("\(n)%").font(.system(size: 9)) } }
            }
        }
        .chartXAxis(.hidden)
        .frame(height: 110)
        .accessibilityLabel(memory ? "Memory usage history, past five minutes" : "CPU usage history, past five minutes")
        .overlay(alignment: .center) {
            if history.filter({ (memory ? $0.memory : $0.cpu) != nil }).count < 2 {
                Text("Collecting live samples…").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct KeyValue: View {
    let label: String
    let value: String
    var body: some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value).monospacedDigit()
        }.font(.callout)
    }
}
