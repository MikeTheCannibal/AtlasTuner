import Foundation

/// Pure interpolation helpers used by the editor and for axis-aware value lookups.
public enum Interpolation {

    /// 1D linear interpolation of `x` over a monotonically increasing `axis` with matching
    /// `values`. Clamps to the end values outside the axis range.
    public static func linear(x: Double, axis: [Double], values: [Double]) -> Double {
        guard let first = axis.first, let last = axis.last, axis.count == values.count else {
            return values.first ?? 0
        }
        if x <= first { return values.first ?? 0 }
        if x >= last { return values.last ?? 0 }
        for i in 1..<axis.count where x <= axis[i] {
            let x0 = axis[i - 1], x1 = axis[i]
            let span = x1 - x0
            let t = span == 0 ? 0 : (x - x0) / span
            return values[i - 1] + t * (values[i] - values[i - 1])
        }
        return values.last ?? 0
    }

    /// Fill `region` of `table` by interpolating from its boundary cells along `axis`.
    public static func fill(_ table: CalibrationTable, region: CellRegion, axis: InterpolationAxis) -> CalibrationTable {
        var result = table
        let r = region.clamped(to: table)
        guard r.cellCount > 0 else { return table }

        switch axis {
        case .horizontal:
            for row in r.rows { interpolateRow(&result, row: row, columns: r.columns) }
        case .vertical:
            for column in r.columns { interpolateColumn(&result, column: column, rows: r.rows) }
        case .both:
            bilinear(&result, region: r)
        }
        return result
    }

    private static func interpolateRow(_ table: inout CalibrationTable, row: Int, columns: Range<Int>) {
        guard columns.count >= 2 else { return }
        let lo = columns.lowerBound, hi = columns.upperBound - 1
        let v0 = table.values[row][lo], v1 = table.values[row][hi]
        let span = hi - lo
        for c in columns {
            let t = Double(c - lo) / Double(span)
            table.setValue(v0 + t * (v1 - v0), row: row, column: c)
        }
    }

    private static func interpolateColumn(_ table: inout CalibrationTable, column: Int, rows: Range<Int>) {
        guard rows.count >= 2 else { return }
        let lo = rows.lowerBound, hi = rows.upperBound - 1
        let v0 = table.values[lo][column], v1 = table.values[hi][column]
        let span = hi - lo
        for r in rows {
            let t = Double(r - lo) / Double(span)
            table.setValue(v0 + t * (v1 - v0), row: r, column: column)
        }
    }

    private static func bilinear(_ table: inout CalibrationTable, region: CellRegion) {
        let rLo = region.rows.lowerBound, rHi = region.rows.upperBound - 1
        let cLo = region.columns.lowerBound, cHi = region.columns.upperBound - 1
        guard rHi > rLo, cHi > cLo else { return }
        let q11 = table.values[rLo][cLo]
        let q12 = table.values[rLo][cHi]
        let q21 = table.values[rHi][cLo]
        let q22 = table.values[rHi][cHi]
        let rSpan = Double(rHi - rLo), cSpan = Double(cHi - cLo)
        for r in region.rows {
            let ty = Double(r - rLo) / rSpan
            for c in region.columns {
                let tx = Double(c - cLo) / cSpan
                let top = q11 + tx * (q12 - q11)
                let bottom = q21 + tx * (q22 - q21)
                table.setValue(top + ty * (bottom - top), row: r, column: c)
            }
        }
    }
}
