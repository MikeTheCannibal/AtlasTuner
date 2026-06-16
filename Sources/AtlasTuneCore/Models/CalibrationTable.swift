import Foundation

/// An editable, in-memory view of one table: engineering values plus resolved axes.
///
/// This is the unit the editor, renderer and difference engine all operate on. It is fully
/// decoupled from byte layout — ``TableAccessor`` bridges it to and from a ``BINImage``.
public struct CalibrationTable: Sendable, Equatable {
    public let definition: TableDefinition
    /// Resolved X (column) breakpoints in engineering units. Empty for scalar tables.
    public var xAxis: [Double]
    /// Resolved Y (row) breakpoints in engineering units. Empty for 1D/scalar tables.
    public var yAxis: [Double]
    /// Engineering values, row-major: `values[row][column]`.
    public var values: [[Double]]

    public init(definition: TableDefinition, xAxis: [Double], yAxis: [Double], values: [[Double]]) {
        self.definition = definition
        self.xAxis = xAxis
        self.yAxis = yAxis
        self.values = values
    }

    public var rows: Int { definition.rows }
    public var columns: Int { definition.columns }

    public func value(row: Int, column: Int) -> Double {
        values[row][column]
    }

    public mutating func setValue(_ value: Double, row: Int, column: Int) {
        let clamped = definition.valueRange.map { min(max(value, $0.lowerBound), $0.upperBound) } ?? value
        values[row][column] = clamped
    }

    /// Flattened engineering values in row-major order — handy for rendering and stats.
    public var flatValues: [Double] { values.flatMap { $0 } }

    public var minValue: Double { flatValues.min() ?? 0 }
    public var maxValue: Double { flatValues.max() ?? 0 }
}
