import Foundation

struct ResultGate {
    private(set) var version = WorkVersion()
    mutating func contentChanged() { version.content &+= 1 }
    mutating func regionChanged() { version.region &+= 1; version.content = 0 }
    func accepts(_ submitted: WorkVersion) -> Bool { version == submitted }
}

struct LatencySamples {
    private(set) var values: [Double] = []
    mutating func append(_ value: Double) {
        guard value.isFinite, value >= 0 else { return }
        values.append(value)
        if values.count > 600 { values.removeFirst(values.count - 600) }
    }
    func percentile(_ p: Double) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        return sorted[min(sorted.count - 1, Int(Double(sorted.count - 1) * p))]
    }
}
