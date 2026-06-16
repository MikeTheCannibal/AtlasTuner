import Foundation

/// 3x3 box-average smoothing constrained to a selection. Neighbours outside the selection are
/// excluded so smoothing never bleeds beyond what the tuner highlighted.
public enum Smoothing {
    public static func smooth(_ table: CalibrationTable, region: CellRegion, passes: Int = 1) -> CalibrationTable {
        var result = table
        let r = region.clamped(to: table)
        guard r.cellCount > 1, passes > 0 else { return result }

        let rowsSet = Set(r.rows)
        let colsSet = Set(r.columns)

        for _ in 0..<passes {
            let source = result.values
            for row in r.rows {
                for column in r.columns {
                    var sum = 0.0
                    var count = 0
                    for dr in -1...1 {
                        for dc in -1...1 {
                            let nr = row + dr, nc = column + dc
                            guard rowsSet.contains(nr), colsSet.contains(nc) else { continue }
                            sum += source[nr][nc]
                            count += 1
                        }
                    }
                    if count > 0 { result.setValue(sum / Double(count), row: row, column: column) }
                }
            }
        }
        return result
    }
}
