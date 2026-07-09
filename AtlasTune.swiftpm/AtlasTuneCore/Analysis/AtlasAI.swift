import Foundation

/// Advisory datalog analysis. Atlas AI reads a recorded ``LogSession``, maps each operating point
/// onto the cells of an open table (the same nearest-breakpoint mapping the active-cell tracker
/// uses), and flags regions showing knock, lean mixture, or boost that misses its target. It is
/// **strictly advisory**: it produces ``AtlasFinding`` suggestions and never edits a table or image.
public struct AtlasAI: Sendable {
    public struct Thresholds: Sendable {
        /// Knock-retard magnitude (degrees) at or above which a sample counts as a knock event.
        public var knockRetardDegrees: Double
        /// Lambda at or above which a sample counts as lean (higher lambda = leaner).
        public var maxLambda: Double
        /// Only judge lambda as lean when engine load (the y channel) is at least this — lean
        /// cruise is normal; lean under load is the danger.
        public var leanMinLoad: Double
        /// Absolute boost error (psi) at or above which actual-vs-target counts as a deviation.
        public var boostDeviationPsi: Double
        /// Ignore a (cell, category) unless at least this many offending samples land there. The
        /// default is 1: in a real pull the car sweeps through cells, so a dangerous event (e.g.
        /// several degrees of knock) often hits each cell only once and must still surface — the
        /// thresholds above are the real noise gate. Raise this to require sustained behaviour.
        public var minSamplesPerCell: Int

        public init(
            knockRetardDegrees: Double = 1.0,
            maxLambda: Double = 0.90,
            leanMinLoad: Double = 70,
            boostDeviationPsi: Double = 2.0,
            minSamplesPerCell: Int = 1
        ) {
            self.knockRetardDegrees = knockRetardDegrees
            self.maxLambda = maxLambda
            self.leanMinLoad = leanMinLoad
            self.boostDeviationPsi = boostDeviationPsi
            self.minSamplesPerCell = minSamplesPerCell
        }
    }

    public let thresholds: Thresholds

    public init(thresholds: Thresholds = Thresholds()) {
        self.thresholds = thresholds
    }

    /// Analyse a session against a table, mapping the `x`/`y` channels onto the table's axes.
    /// Channels that a category needs but the log lacks simply produce no findings for that
    /// category — the analysis degrades gracefully rather than failing.
    public func analyze(
        _ session: LogSession,
        table: CalibrationTable,
        x: LogChannel = .rpm,
        y: LogChannel = .load
    ) -> AnalysisReport {
        let xAxis = table.xAxis.isEmpty ? Array(0..<max(1, table.columns)).map(Double.init) : table.xAxis
        let yAxis = table.yAxis
        let boostTarget = Self.boostTargetChannelID(in: session)

        var accumulators: [Accumulator: Bucket] = [:]
        var analyzed = 0

        for sample in session.samples {
            guard let xValue = sample.value(x) else { continue }
            analyzed += 1
            let column = ActiveCellTracker.nearestIndex(of: xValue, in: xAxis)
            let loadValue = sample.value(y)
            let row = (yAxis.isEmpty || loadValue == nil) ? 0 : ActiveCellTracker.nearestIndex(of: loadValue!, in: yAxis)
            let cell = CellAddress(row: row, column: column)

            if let knock = sample.value(.knock) {
                let magnitude = abs(knock)
                if magnitude >= thresholds.knockRetardDegrees {
                    accumulators[Accumulator(cell, .knock), default: Bucket()].add(magnitude)
                }
            }
            if let lambda = sample.value(.lambda), let load = loadValue,
               load >= thresholds.leanMinLoad, lambda >= thresholds.maxLambda {
                accumulators[Accumulator(cell, .lean), default: Bucket()].add(lambda)
            }
            if let targetID = boostTarget, let actual = sample.value(.boost),
               let target = sample.value(channelID: targetID) {
                let deviation = actual - target
                if abs(deviation) >= thresholds.boostDeviationPsi {
                    accumulators[Accumulator(cell, .boostDeviation), default: Bucket()].add(deviation)
                }
            }
        }

        let findings = accumulators
            .filter { $0.value.count >= thresholds.minSamplesPerCell }
            .map { key, bucket in makeFinding(key.cell, key.category, bucket) }
            .sorted { lhs, rhs in
                lhs.severity != rhs.severity ? lhs.severity > rhs.severity : lhs.sampleCount > rhs.sampleCount
            }

        return AnalysisReport(findings: findings, totalSamples: session.samples.count, analyzedSamples: analyzed)
    }

    // MARK: Finding construction

    private func makeFinding(_ cell: CellAddress, _ category: AtlasCategory, _ bucket: Bucket) -> AtlasFinding {
        // Worst reading drives severity; boost keeps the signed peak so we can say over/under.
        let peakMagnitude = max(abs(bucket.peakLow), abs(bucket.peakHigh))
        let signedPeak = abs(bucket.peakHigh) >= abs(bucket.peakLow) ? bucket.peakHigh : bucket.peakLow
        let mean = bucket.sum / Double(bucket.count)

        let severity: AtlasSeverity
        let message: String
        let suggestion: String

        switch category {
        case .knock:
            severity = Self.severity(value: peakMagnitude, threshold: thresholds.knockRetardDegrees)
            message = String(format: "Knock retard up to %.1f° (avg %.1f°) across %d samples.",
                             peakMagnitude, abs(mean), bucket.count)
            suggestion = "Consider pulling ignition timing in this region, or verify fuel quality."
        case .lean:
            // Lambda sits near 1, so absolute exceedance is more meaningful than a ratio.
            severity = Self.leanSeverity(peakLambda: peakMagnitude, maxLambda: thresholds.maxLambda)
            message = String(format: "Lambda reached %.2f (avg %.2f), leaner than %.2f, under load.",
                             peakMagnitude, mean, thresholds.maxLambda)
            suggestion = "Consider richening fuelling (lower target lambda) in this region."
        case .boostDeviation:
            severity = Self.severity(value: peakMagnitude, threshold: thresholds.boostDeviationPsi)
            let sense = signedPeak >= 0 ? "over" : "under"
            message = String(format: "Boost %@ target by up to %.1f psi (avg %.1f) here.",
                             sense, peakMagnitude, abs(mean))
            suggestion = signedPeak >= 0
                ? "Consider lowering the boost target or wastegate duty in this region."
                : "Consider raising the boost target or wastegate duty in this region."
        }

        return AtlasFinding(
            category: category, severity: severity, cell: cell,
            sampleCount: bucket.count, peak: peakMagnitude, mean: mean,
            message: message, suggestion: suggestion
        )
    }

    /// Severity from how far a reading exceeds its threshold: ≥3× critical, ≥1.5× warning, else
    /// info. Suited to metrics that scale up from zero (knock degrees, boost psi).
    static func severity(value: Double, threshold: Double) -> AtlasSeverity {
        guard threshold > 0 else { return .warning }
        let ratio = value / threshold
        if ratio >= 3 { return .critical }
        if ratio >= 1.5 { return .warning }
        return .info
    }

    /// Lean severity by absolute lambda exceedance: even a small climb under boost is serious.
    static func leanSeverity(peakLambda: Double, maxLambda: Double) -> AtlasSeverity {
        let delta = peakLambda - maxLambda
        if delta >= 0.10 { return .critical }
        if delta >= 0.04 { return .warning }
        return .info
    }

    /// The session channel id carrying a boost *target*, if present (e.g. the importer preserves an
    /// MHD "Boost Target" column as `boost_target`).
    static func boostTargetChannelID(in session: LogSession) -> String? {
        for channel in session.channels {
            let id = channel.id.lowercased()
            let name = channel.name.lowercased()
            if id == LogChannel.boost.id { continue }
            if (id.contains("boost") || name.contains("boost")) &&
               (id.contains("target") || name.contains("target") || id.contains("req") || name.contains("request")) {
                return channel.id
            }
        }
        return nil
    }

    // MARK: Aggregation helpers

    private struct Accumulator: Hashable {
        let cell: CellAddress
        let category: AtlasCategory
        init(_ cell: CellAddress, _ category: AtlasCategory) { self.cell = cell; self.category = category }
    }

    private struct Bucket {
        var count = 0
        var sum = 0.0
        var peakLow = 0.0   // most-negative reading (for signed boost deviation)
        var peakHigh = 0.0  // most-positive reading

        mutating func add(_ value: Double) {
            count += 1
            sum += value
            peakHigh = max(peakHigh, value)
            peakLow = min(peakLow, value)
        }
    }
}
