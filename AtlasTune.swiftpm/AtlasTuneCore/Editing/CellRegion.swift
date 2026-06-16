import Foundation

/// A rectangular block of cells within a table, expressed as half-open row/column ranges.
/// Most tuner edits operate on a contiguous selection, which also makes interpolation
/// (corner-anchored) well defined.
public struct CellRegion: Sendable, Equatable {
    public var rows: Range<Int>
    public var columns: Range<Int>

    public init(rows: Range<Int>, columns: Range<Int>) {
        self.rows = rows
        self.columns = columns
    }

    /// A single-cell region.
    public init(row: Int, column: Int) {
        self.rows = row..<(row + 1)
        self.columns = column..<(column + 1)
    }

    /// The whole table.
    public static func all(_ table: CalibrationTable) -> CellRegion {
        CellRegion(rows: 0..<table.rows, columns: 0..<table.columns)
    }

    public var cellCount: Int { rows.count * columns.count }
    public var isSingleCell: Bool { rows.count == 1 && columns.count == 1 }

    /// Every (row, column) pair in the region, row-major.
    public var cells: [(row: Int, column: Int)] {
        rows.flatMap { r in columns.map { c in (r, c) } }
    }

    /// Clamp the region to the bounds of `table`.
    public func clamped(to table: CalibrationTable) -> CellRegion {
        let r = max(0, rows.lowerBound)..<min(table.rows, rows.upperBound)
        let c = max(0, columns.lowerBound)..<min(table.columns, columns.upperBound)
        return CellRegion(rows: r, columns: c)
    }
}
