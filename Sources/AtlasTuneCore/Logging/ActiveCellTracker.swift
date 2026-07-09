import Foundation

/// A cell coordinate within a table.
public struct CellAddress: Sendable, Hashable {
    public let row: Int
    public let column: Int
    public init(row: Int, column: Int) {
        self.row = row
        self.column = column
    }
}

/// The flagship "where does the car live" feature.
///
/// Given a table's resolved axes, the tracker maps each live operating point (e.g. current RPM
/// and load) to the nearest table cell, then accumulates hit frequency and recency. The result
/// drives the active-cell highlight, the recently-visited trail, and the heat-map overlay.
public struct ActiveCellTracker: Sendable {
    public let rows: Int
    public let columns: Int
    /// Column-axis breakpoints (X). Required.
    private let xAxis: [Double]
    /// Row-axis breakpoints (Y). Empty for 1D tables (single row).
    private let yAxis: [Double]

    /// hits[row][column] — number of samples that landed on each cell.
    public private(set) var hits: [[Int]]
    /// Monotonic visit index per cell; higher means more recently visited (0 = never).
    public private(set) var lastVisit: [[Int]]
    public private(set) var current: CellAddress?
    private var visitCounter = 0

    public init(table: CalibrationTable) {
        self.rows = max(1, table.rows)
        self.columns = max(1, table.columns)
        self.xAxis = table.xAxis.isEmpty ? Array(0..<columns).map(Double.init) : table.xAxis
        self.yAxis = table.yAxis
        self.hits = Array(repeating: Array(repeating: 0, count: columns), count: rows)
        self.lastVisit = Array(repeating: Array(repeating: 0, count: columns), count: rows)
    }

    /// Replay an entire recorded session, mapping the `x`/`y` channels of each sample onto cells.
    /// Samples missing the x channel are skipped. This is how an imported datalog fills the heat
    /// map in one pass.
    public mutating func record(session: LogSession, x: LogChannel, y: LogChannel) {
        for sample in session.samples {
            guard let xValue = sample.value(x) else { continue }
            record(x: xValue, y: sample.value(y))
        }
    }

    /// Record one operating point and return the cell it mapped to.
    @discardableResult
    public mutating func record(x: Double, y: Double? = nil) -> CellAddress {
        let column = Self.nearestIndex(of: x, in: xAxis)
        let row: Int
        if let y, !yAxis.isEmpty {
            row = Self.nearestIndex(of: y, in: yAxis)
        } else {
            row = 0
        }
        let address = CellAddress(row: row, column: column)
        hits[row][column] += 1
        visitCounter += 1
        lastVisit[row][column] = visitCounter
        current = address
        return address
    }

    public var totalHits: Int { hits.reduce(0) { $0 + $1.reduce(0, +) } }
    public var maxHits: Int { hits.flatMap { $0 }.max() ?? 0 }

    /// Normalised hit frequency in [0, 1] per cell — the heat-map intensity.
    public func heatMap() -> [[Double]] {
        let peak = maxHits
        guard peak > 0 else { return hits.map { $0.map { _ in 0.0 } } }
        return hits.map { $0.map { Double($0) / Double(peak) } }
    }

    /// The `count` most recently visited cells, most recent first.
    public func recentCells(_ count: Int) -> [CellAddress] {
        var visited: [(CellAddress, Int)] = []
        for r in 0..<rows {
            for c in 0..<columns where lastVisit[r][c] > 0 {
                visited.append((CellAddress(row: r, column: c), lastVisit[r][c]))
            }
        }
        return visited.sorted { $0.1 > $1.1 }.prefix(count).map(\.0)
    }

    public mutating func reset() {
        hits = Array(repeating: Array(repeating: 0, count: columns), count: rows)
        lastVisit = Array(repeating: Array(repeating: 0, count: columns), count: rows)
        current = nil
        visitCounter = 0
    }

    /// Index of the breakpoint nearest to `value`. Assumes a non-empty axis.
    static func nearestIndex(of value: Double, in axis: [Double]) -> Int {
        guard !axis.isEmpty else { return 0 }
        var bestIndex = 0
        var bestDistance = Double.infinity
        for (i, breakpoint) in axis.enumerated() {
            let distance = abs(breakpoint - value)
            if distance < bestDistance {
                bestDistance = distance
                bestIndex = i
            }
        }
        return bestIndex
    }
}
