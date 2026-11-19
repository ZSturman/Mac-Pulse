import Foundation

enum ProcessOrder: String, CaseIterable, Identifiable {
    case cpu = "CPU", memory = "Memory"
    var id: String { rawValue }

    func sorted(_ processes: [ProcessReading]) -> [ProcessReading] {
        processes.sorted { lhs, rhs in
            if self == .cpu {
                let left = lhs.cpu ?? -1
                let right = rhs.cpu ?? -1
                return left == right ? lhs.pid < rhs.pid : left > right
            }
            return lhs.memory == rhs.memory ? lhs.pid < rhs.pid : lhs.memory > rhs.memory
        }
    }

    func value(for process: ProcessReading) -> Double? {
        self == .cpu ? process.cpu : Double(process.memory)
    }
}

struct ProcessRankRise: Equatable {
    static let duration: TimeInterval = 2

    let places: Int?
    let time: TimeInterval
}

struct ProcessRanking {
    static let highlightedCount = 5

    private(set) var readings: [ProcessReading] = []
    private(set) var rises: [ProcessIdentity: ProcessRankRise] = [:]

    func updated(with processes: [ProcessReading], order: ProcessOrder, at time: TimeInterval) -> Self {
        var next = Self()
        next.readings = order.sorted(processes)
        let oldRanks = Dictionary(readings.enumerated().compactMap { index, process in
            order.value(for: process).map { _ in (process.id, index) }
        }, uniquingKeysWith: { first, _ in first })
        guard !oldRanks.isEmpty else { return next }

        for (rank, process) in next.readings.prefix(Self.highlightedCount).enumerated() {
            guard let value = order.value(for: process), value > 0 else { continue }
            if let oldRank = oldRanks[process.id] {
                if oldRank > rank {
                    next.rises[process.id] = ProcessRankRise(places: oldRank - rank, time: time)
                } else if oldRank == rank, let rise = rises[process.id], time - rise.time < ProcessRankRise.duration {
                    next.rises[process.id] = rise
                }
            } else {
                next.rises[process.id] = ProcessRankRise(places: nil, time: time)
            }
        }
        return next
    }
}
