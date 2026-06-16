import Foundation

/// Per-cell change between two versions of one table.
public struct CellDifference: Sendable, Equatable {
    public let row: Int
    public let column: Int
    public let before: Double
    public let after: Double
    public var delta: Double { after - before }
    public var percent: Double { before == 0 ? .infinity : (after - before) / before * 100 }
}

/// All changes to a single table between two images.
public struct TableDifference: Sendable, Equatable {
    public let tableID: String
    public let tableName: String
    public let category: CalibrationCategory
    public let cells: [CellDifference]

    public var changedCount: Int { cells.count }
    public var maxAbsoluteDelta: Double { cells.map { abs($0.delta) }.max() ?? 0 }
    public var hasChanges: Bool { !cells.isEmpty }
}

/// Whole-image comparison summary.
public struct CalibrationDifference: Sendable, Equatable {
    public let tables: [TableDifference]
    public var changedTables: [TableDifference] { tables.filter(\.hasChanges) }
    public var totalChangedCells: Int { tables.reduce(0) { $0 + $1.changedCount } }
    public var isIdentical: Bool { totalChangedCells == 0 }
}

/// Computes structured differences between two calibrations using a shared definition package.
/// This powers the revision compare view and the export "metadata report".
public struct DifferenceEngine: Sendable {
    private let accessor = TableAccessor()
    /// Engineering-value tolerance below which two cells are considered equal.
    public let tolerance: Double

    public init(tolerance: Double = 1e-6) {
        self.tolerance = tolerance
    }

    public func compare(_ before: BINImage, _ after: BINImage, using package: DefinitionPackage) -> CalibrationDifference {
        var tableDiffs: [TableDifference] = []
        for definition in package.tables {
            guard let b = try? accessor.read(definition, from: before),
                  let a = try? accessor.read(definition, from: after) else { continue }

            var cells: [CellDifference] = []
            for row in 0..<definition.rows {
                for column in 0..<definition.columns {
                    let bv = b.values[row][column]
                    let av = a.values[row][column]
                    if abs(av - bv) > tolerance {
                        cells.append(CellDifference(row: row, column: column, before: bv, after: av))
                    }
                }
            }
            tableDiffs.append(TableDifference(
                tableID: definition.id,
                tableName: definition.name,
                category: definition.category,
                cells: cells
            ))
        }
        return CalibrationDifference(tables: tableDiffs)
    }
}
