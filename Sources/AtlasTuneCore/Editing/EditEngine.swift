import Foundation

/// Applies ``EditOperation``s to a ``CalibrationTable`` over a ``CellRegion``. All operations
/// are pure: they return a new table and never mutate the input, so the result can be pushed
/// straight onto the undo stack.
public struct EditEngine: Sendable {
    public init() {}

    public func apply(_ operation: EditOperation, to table: CalibrationTable, region: CellRegion) -> CalibrationTable {
        let r = region.clamped(to: table)
        guard r.cellCount > 0 else { return table }

        switch operation {
        case .set(let v):
            return transform(table, r) { _ in v }
        case .add(let v):
            return transform(table, r) { $0 + v }
        case .subtract(let v):
            return transform(table, r) { $0 - v }
        case .multiply(let v):
            return transform(table, r) { $0 * v }
        case .divide(let v):
            guard v != 0 else { return table }
            return transform(table, r) { $0 / v }
        case .percentChange(let pct):
            let k = 1 + pct / 100
            return transform(table, r) { $0 * k }
        case .interpolate(let axis):
            return Interpolation.fill(table, region: r, axis: axis)
        case .smooth(let passes):
            return Smoothing.smooth(table, region: r, passes: passes)
        case .flatten:
            let mean = average(of: table, region: r)
            return transform(table, r) { _ in mean }
        case .paste(let block):
            return paste(block, into: table, at: r)
        }
    }

    // MARK: Helpers

    private func transform(_ table: CalibrationTable, _ region: CellRegion, _ f: (Double) -> Double) -> CalibrationTable {
        var result = table
        for (row, column) in region.cells {
            result.setValue(f(table.values[row][column]), row: row, column: column)
        }
        return result
    }

    private func average(of table: CalibrationTable, region: CellRegion) -> Double {
        let cells = region.cells
        guard !cells.isEmpty else { return 0 }
        let sum = cells.reduce(0.0) { $0 + table.values[$1.row][$1.column] }
        return sum / Double(cells.count)
    }

    private func paste(_ block: [[Double]], into table: CalibrationTable, at region: CellRegion) -> CalibrationTable {
        var result = table
        let originRow = region.rows.lowerBound
        let originColumn = region.columns.lowerBound
        for (dr, blockRow) in block.enumerated() {
            for (dc, value) in blockRow.enumerated() {
                let row = originRow + dr, column = originColumn + dc
                guard row < table.rows, column < table.columns else { continue }
                result.setValue(value, row: row, column: column)
            }
        }
        return result
    }
}
