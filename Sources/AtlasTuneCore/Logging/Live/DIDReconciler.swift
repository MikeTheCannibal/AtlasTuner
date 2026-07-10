import Foundation

/// A timed raw reading of one DID during a capture drive: seconds from capture start, and the raw
/// numeric value decoded from the response bytes (before any scaling).
public struct TimedRaw: Sendable, Equatable {
    public let time: TimeInterval
    public let raw: Double
    public init(time: TimeInterval, raw: Double) {
        self.time = time
        self.raw = raw
    }
}

/// A captured DID's raw time-series, as recorded by ``DIDCapture`` on the car.
public struct CapturedDID: Sendable, Equatable {
    public let did: UInt16
    public let byteLength: Int
    public let samples: [TimedRaw]
    public init(did: UInt16, byteLength: Int, samples: [TimedRaw]) {
        self.did = did
        self.byteLength = byteLength
        self.samples = samples
    }
}

/// The reconciler's guess for one channel: which DID feeds it, the scaling fit from the reference
/// data, and how confident the match is.
public struct ChannelCandidate: Sendable, Equatable {
    public let channel: LogChannel
    public let did: UInt16
    public let byteLength: Int
    public let scaling: Scaling
    /// |Pearson r| between the DID's raw series and the reference channel (1 = perfect).
    public let correlation: Double
    /// |r| of the next-best DID — a small gap from `correlation` means the match is ambiguous.
    public let runnerUpCorrelation: Double
    /// Time shift (seconds) applied to align the capture to the reference, from the RPM anchor.
    public let appliedLag: TimeInterval

    /// The candidate as a ready-to-use live identifier (big-endian, width from the response length).
    public var identifier: UDSDataIdentifier {
        UDSDataIdentifier(channel: channel, did: did, byteOffset: 0,
                          dataType: Self.dataType(forWidth: byteLength),
                          byteOrder: .bigEndian, scaling: scaling)
    }

    /// How trustworthy the mapping is: high correlation *and* a clear margin over the runner-up.
    public var isConfident: Bool { correlation >= 0.9 && (correlation - runnerUpCorrelation) >= 0.1 }

    static func dataType(forWidth width: Int) -> DataType {
        switch width {
        case 1: return .uint8
        case 4: return .uint32
        default: return .uint16
        }
    }
}

/// Reconciles the real DID map from data. Given a raw DID capture and a labelled reference log
/// (an MHD/bootmod3 CSV of the *same* drive), it aligns the two timelines on their shared RPM
/// trace, then for each reference channel finds the raw DID series that best tracks it and fits the
/// linear scaling by least squares. Correlation is invariant to linear scaling, so matching on the
/// raw integer works, and the regression recovers `factor`/`offset` directly.
///
/// Pure and deterministic — validated against synthetic captures where the true map is known.
public struct DIDReconciler: Sendable {
    public struct Options: Sendable {
        /// Half-width of the lag search (seconds) when aligning capture to reference on RPM.
        public var maxLag: TimeInterval
        /// Lag search step (seconds).
        public var lagStep: TimeInterval
        /// Ignore a candidate whose best correlation is below this.
        public var minCorrelation: Double

        public init(maxLag: TimeInterval = 3.0, lagStep: TimeInterval = 0.05, minCorrelation: Double = 0.5) {
            self.maxLag = maxLag
            self.lagStep = lagStep
            self.minCorrelation = minCorrelation
        }
    }

    public let options: Options
    public init(options: Options = Options()) { self.options = options }

    public func reconcile(
        capture: [CapturedDID],
        reference: LogSession,
        anchor: LogChannel = .rpm
    ) -> [ChannelCandidate] {
        let series = capture.map { (did: $0, points: $0.samples.sorted { $0.time < $1.time }) }
            .filter { $0.points.count >= 2 }
        guard !series.isEmpty else { return [] }

        // 1. Align clocks: find the lag that best matches the anchor channel to any DID.
        let lag = anchorLag(reference: reference, anchor: anchor, series: series)

        // 2. For each reference channel, pick the best DID at that lag and fit scaling.
        var candidates: [ChannelCandidate] = []
        for channel in reference.channels {
            let ref = reference.series(channel)
            guard ref.count >= 2 else { continue }
            let grid = ref.map(\.time)
            let target = ref.map(\.value)

            var scored: [(did: CapturedDID, r: Double, slope: Double, intercept: Double)] = []
            for entry in series {
                let raw = resample(entry.points, onto: grid, lag: lag)
                guard let (r, slope, intercept) = fit(x: raw, y: target) else { continue }
                scored.append((entry.did, abs(r), slope, intercept))
            }
            scored.sort { $0.r > $1.r }
            guard let best = scored.first, best.r >= options.minCorrelation else { continue }
            let runnerUp = scored.count > 1 ? scored[1].r : 0

            candidates.append(ChannelCandidate(
                channel: channel, did: best.did.did, byteLength: best.did.byteLength,
                scaling: Scaling(factor: best.slope, offset: best.intercept,
                                 decimals: max(0, channel.unit == "rpm" ? 0 : 2)),
                correlation: best.r, runnerUpCorrelation: runnerUp, appliedLag: lag
            ))
        }
        return candidates.sorted { $0.correlation > $1.correlation }
    }

    // MARK: Alignment

    /// Search lags to maximise the anchor channel's correlation with its best-matching DID.
    private func anchorLag(reference: LogSession, anchor: LogChannel,
                           series: [(did: CapturedDID, points: [TimedRaw])]) -> TimeInterval {
        let ref = reference.series(anchor)
        guard ref.count >= 2 else { return 0 }
        let grid = ref.map(\.time)
        let target = ref.map(\.value)

        var bestLag = 0.0
        var bestR = -1.0
        var lag = -options.maxLag
        while lag <= options.maxLag + 1e-9 {
            for entry in series {
                let raw = resample(entry.points, onto: grid, lag: lag)
                if let (r, _, _) = fit(x: raw, y: target), abs(r) > bestR {
                    bestR = abs(r); bestLag = lag
                }
            }
            lag += options.lagStep
        }
        return bestLag
    }

    // MARK: Numerics

    /// Sample a sorted (time, raw) series at each grid time (grid shifted by `lag`), by linear
    /// interpolation; clamps to the series' endpoints outside its range.
    private func resample(_ points: [TimedRaw], onto grid: [TimeInterval], lag: TimeInterval) -> [Double] {
        var out = [Double](repeating: 0, count: grid.count)
        var j = 0
        for (i, t0) in grid.enumerated() {
            let t = t0 + lag
            if t <= points.first!.time { out[i] = points.first!.raw; continue }
            if t >= points.last!.time { out[i] = points.last!.raw; continue }
            while j < points.count - 1 && points[j + 1].time < t { j += 1 }
            while j > 0 && points[j].time > t { j -= 1 }
            let a = points[j], b = points[j + 1]
            let span = b.time - a.time
            out[i] = span > 0 ? a.raw + (b.raw - a.raw) * (t - a.time) / span : a.raw
        }
        return out
    }

    /// Pearson r plus the least-squares line y = slope·x + intercept. Returns `nil` if x is
    /// constant (no correlation defined — e.g. a DID that never changes).
    private func fit(x: [Double], y: [Double]) -> (r: Double, slope: Double, intercept: Double)? {
        let n = Double(min(x.count, y.count))
        guard n >= 2 else { return nil }
        let sx = x.reduce(0, +), sy = y.reduce(0, +)
        let mx = sx / n, my = sy / n
        var sxx = 0.0, syy = 0.0, sxy = 0.0
        for i in 0..<Int(n) {
            let dx = x[i] - mx, dy = y[i] - my
            sxx += dx * dx; syy += dy * dy; sxy += dx * dy
        }
        guard sxx > 1e-12, syy > 1e-12 else { return nil }
        let slope = sxy / sxx
        let intercept = my - slope * mx
        let r = sxy / (sxx.squareRoot() * syy.squareRoot())
        return (r, slope, intercept)
    }
}
