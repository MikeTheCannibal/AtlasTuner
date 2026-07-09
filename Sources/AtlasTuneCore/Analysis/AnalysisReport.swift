import Foundation

/// The class of issue Atlas AI detects.
public enum AtlasCategory: String, Sendable, Codable, CaseIterable {
    case knock
    case lean
    case rich
    case boostDeviation

    public var displayName: String {
        switch self {
        case .knock: return "Knock"
        case .lean: return "Lean Mixture"
        case .rich: return "Rich Mixture"
        case .boostDeviation: return "Boost Deviation"
        }
    }
}

/// How urgent a finding is.
public enum AtlasSeverity: Int, Sendable, Codable, Comparable, CaseIterable {
    case info = 0
    case warning = 1
    case critical = 2

    public static func < (lhs: AtlasSeverity, rhs: AtlasSeverity) -> Bool { lhs.rawValue < rhs.rawValue }

    public var displayName: String {
        switch self {
        case .info: return "Info"
        case .warning: return "Warning"
        case .critical: return "Critical"
        }
    }
}

/// One advisory finding: a table cell where the log showed a problem, with supporting stats and a
/// suggested (never auto-applied) action.
public struct AtlasFinding: Sendable, Identifiable, Equatable {
    public let id: UUID
    public let category: AtlasCategory
    public let severity: AtlasSeverity
    public let cell: CellAddress
    /// Number of offending samples that landed on this cell.
    public let sampleCount: Int
    /// Worst reading at this cell: knock retard magnitude (°), the leanest/richest lambda, or the
    /// signed boost error in psi (positive = overboost).
    public let peak: Double
    /// Mean reading across the offending samples.
    public let mean: Double
    public let message: String
    public let suggestion: String

    public init(
        id: UUID = UUID(),
        category: AtlasCategory,
        severity: AtlasSeverity,
        cell: CellAddress,
        sampleCount: Int,
        peak: Double,
        mean: Double,
        message: String,
        suggestion: String
    ) {
        self.id = id
        self.category = category
        self.severity = severity
        self.cell = cell
        self.sampleCount = sampleCount
        self.peak = peak
        self.mean = mean
        self.message = message
        self.suggestion = suggestion
    }

    public static func == (lhs: AtlasFinding, rhs: AtlasFinding) -> Bool {
        lhs.category == rhs.category && lhs.severity == rhs.severity && lhs.cell == rhs.cell
            && lhs.sampleCount == rhs.sampleCount && lhs.peak == rhs.peak && lhs.mean == rhs.mean
    }
}

/// The result of analysing a session against a table. Advisory only — it describes what happened,
/// never mutating anything.
public struct AnalysisReport: Sendable, Equatable {
    /// Findings sorted most-severe first.
    public let findings: [AtlasFinding]
    /// Total samples in the analysed session.
    public let totalSamples: Int
    /// Samples that mapped to a cell (i.e. carried the x channel).
    public let analyzedSamples: Int

    public init(findings: [AtlasFinding], totalSamples: Int, analyzedSamples: Int) {
        self.findings = findings
        self.totalSamples = totalSamples
        self.analyzedSamples = analyzedSamples
    }

    public var isClean: Bool { findings.isEmpty }

    public func findings(_ category: AtlasCategory) -> [AtlasFinding] {
        findings.filter { $0.category == category }
    }

    public var mostSevere: AtlasSeverity? { findings.map(\.severity).max() }

    /// Count of findings at a given severity.
    public func count(_ severity: AtlasSeverity) -> Int {
        findings.filter { $0.severity == severity }.count
    }

    /// The bounding region of all findings in a category — handy for highlighting the affected
    /// area of the map. `nil` if the category has no findings.
    public func boundingRegion(for category: AtlasCategory) -> CellRegion? {
        let cells = findings(category).map(\.cell)
        guard let first = cells.first else { return nil }
        var minRow = first.row, maxRow = first.row
        var minCol = first.column, maxCol = first.column
        for cell in cells.dropFirst() {
            minRow = min(minRow, cell.row); maxRow = max(maxRow, cell.row)
            minCol = min(minCol, cell.column); maxCol = max(maxCol, cell.column)
        }
        return CellRegion(rows: minRow..<(maxRow + 1), columns: minCol..<(maxCol + 1))
    }
}
