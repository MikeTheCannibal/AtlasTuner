import Foundation

/// A quantified, safety-clamped adjustment suggested for one finding: which cells, what edit, and
/// why. The engine only *suggests* — applying is always an explicit user action, and it flows
/// through the normal `EditEngine` path (undoable, revisioned, clamped to the table's safe range).
public struct SuggestedCorrection: Sendable, Identifiable, Equatable {
    public let id: UUID
    public let category: AtlasCategory
    public let severity: AtlasSeverity
    /// Cells the edit targets.
    public let region: CellRegion
    /// The staged edit, ready for `EditEngine.apply` / `WorkspaceModel.applyEdit`.
    public let operation: EditOperation
    /// One line, quantified: "Pull 1.0° timing" / "Richen fuelling 3.0%".
    public let summary: String
    /// The finding that motivated it.
    public let rationale: String
    /// True when the per-pass step limit reduced the full computed correction — meaning the log
    /// asked for more than one safe step; re-log and iterate.
    public let stepLimited: Bool

    public init(id: UUID = UUID(), category: AtlasCategory, severity: AtlasSeverity,
                region: CellRegion, operation: EditOperation, summary: String,
                rationale: String, stepLimited: Bool) {
        self.id = id
        self.category = category
        self.severity = severity
        self.region = region
        self.operation = operation
        self.summary = summary
        self.rationale = rationale
        self.stepLimited = stepLimited
    }

    public static func == (lhs: SuggestedCorrection, rhs: SuggestedCorrection) -> Bool {
        lhs.category == rhs.category && lhs.region == rhs.region && lhs.operation == rhs.operation
            && lhs.summary == rhs.summary && lhs.stepLimited == rhs.stepLimited
    }
}

/// Turns an `AnalysisReport` into quantified `SuggestedCorrection`s for the **open table** — and
/// only when that table's category matches the finding (knock corrections belong on an ignition
/// map, mixture corrections on a fuel map, boost corrections on a boost/wastegate map). Each pass
/// suggests a deliberately small step: apply, re-log, analyze again — the loop converges on the
/// data instead of chasing one log's worst sample.
public struct CorrectionEngine: Sendable {
    /// Per-iteration safety limits. `gain` scales the measured error before clamping, so one pass
    /// never corrects the full observed error (damping against sensor noise and oscillation).
    public struct StepLimits: Sendable {
        /// Fraction of the measured error to correct per pass.
        public var gain: Double
        /// Hard cap on timing change per pass (degrees).
        public var maxTimingStepDegrees: Double
        /// Hard cap on fuelling change per pass (percent).
        public var maxFuelStepPercent: Double
        /// Hard cap on boost-target change per pass (psi).
        public var maxBoostStepPsi: Double

        public init(gain: Double = 0.5,
                    maxTimingStepDegrees: Double = 1.0,
                    maxFuelStepPercent: Double = 3.0,
                    maxBoostStepPsi: Double = 1.0) {
            self.gain = gain
            self.maxTimingStepDegrees = maxTimingStepDegrees
            self.maxFuelStepPercent = maxFuelStepPercent
            self.maxBoostStepPsi = maxBoostStepPsi
        }
    }

    public let limits: StepLimits
    public let thresholds: AtlasAI.Thresholds

    public init(limits: StepLimits = StepLimits(), thresholds: AtlasAI.Thresholds = .init()) {
        self.limits = limits
        self.thresholds = thresholds
    }

    /// Corrections applicable to `table` for the report's findings, most severe first. Findings
    /// whose category doesn't belong on this table produce nothing here (open the right map).
    public func corrections(for report: AnalysisReport, table: CalibrationTable) -> [SuggestedCorrection] {
        report.findings.compactMap { correction(for: $0, table: table) }
    }

    public func correction(for finding: AtlasFinding, table: CalibrationTable) -> SuggestedCorrection? {
        let region = CellRegion(row: finding.cell.row, column: finding.cell.column).clamped(to: table)
        guard region.cellCount > 0 else { return nil }

        switch (finding.category, table.definition.category) {
        case (.knock, .ignition):
            // Pull a fraction of the observed retard, capped per pass.
            let wanted = abs(finding.peak) * limits.gain
            let step = min(wanted, limits.maxTimingStepDegrees)
            guard step > 0 else { return nil }
            return SuggestedCorrection(
                category: .knock, severity: finding.severity, region: region,
                operation: .subtract(round1(step)),
                summary: String(format: "Pull %.1f° timing at row %d, col %d",
                                round1(step), finding.cell.row, finding.cell.column),
                rationale: finding.message, stepLimited: wanted > step
            )

        case (.lean, .fuel), (.rich, .fuel):
            // The fuel multiplier that would land mid-band, damped and capped. For lean, the
            // measured lambda exceeds the band top; for rich it undershoots the band bottom.
            let target = (thresholds.maxLambda + thresholds.richLambda) / 2
            guard target > 0, finding.peak > 0 else { return nil }
            let fullPercent = (finding.peak / target - 1) * 100     // + = needs fuel, − = too much
            let damped = fullPercent * limits.gain
            let magnitude = min(abs(damped), limits.maxFuelStepPercent)
            guard magnitude > 0.05 else { return nil }
            // On a lambda-target table richer = LOWER value, so the sign flips.
            let enriching = damped > 0
            let sign: Double = Self.isLambdaTargetTable(table) ? (enriching ? -1 : 1)
                                                               : (enriching ? 1 : -1)
            return SuggestedCorrection(
                category: finding.category, severity: finding.severity, region: region,
                operation: .percentChange(round1(magnitude) * sign),
                summary: String(format: "%@ fuelling %.1f%% at row %d, col %d",
                                enriching ? "Richen" : "Lean", round1(magnitude),
                                finding.cell.row, finding.cell.column),
                rationale: finding.message, stepLimited: abs(damped) > magnitude
            )

        case (.boostDeviation, .boost):
            // Overboost (+peak) lowers the target; underboost raises it.
            let wanted = abs(finding.peak) * limits.gain
            let step = min(wanted, limits.maxBoostStepPsi)
            guard step > 0 else { return nil }
            let over = finding.peak >= 0
            return SuggestedCorrection(
                category: .boostDeviation, severity: finding.severity, region: region,
                operation: over ? .subtract(round1(step)) : .add(round1(step)),
                summary: String(format: "%@ boost target %.1f psi at row %d, col %d",
                                over ? "Lower" : "Raise", round1(step),
                                finding.cell.row, finding.cell.column),
                rationale: finding.message, stepLimited: wanted > step
            )

        default:
            return nil
        }
    }

    /// Lambda-target tables store the *desired lambda*, where richer = lower value. Detected from
    /// the definition's unit/name so mixture corrections flip sign correctly.
    static func isLambdaTargetTable(_ table: CalibrationTable) -> Bool {
        let unit = table.definition.unit.lowercased()
        let name = table.definition.name.lowercased()
        return unit.contains("λ") || unit.contains("lambda") || name.contains("lambda")
    }

    private func round1(_ v: Double) -> Double { (v * 10).rounded() / 10 }
}
