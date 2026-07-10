import Foundation

/// Records raw DID values over time during a capture drive. Given the responders a ``DIDScanner``
/// found, it polls them in a loop for a fixed duration, timestamping each cycle, and returns one
/// raw time-series per DID for the ``DIDReconciler`` to correlate against a labelled MHD log.
///
/// Each DID is treated as a single big-endian value of its response width — enough to correlate a
/// scalar signal. DIDs that pack several fields will correlate poorly and surface as low-confidence,
/// which is the honest outcome until per-offset extraction is added.
public actor DIDCapture {
    private let client: DoIPClient

    public init(client: DoIPClient) {
        self.client = client
    }

    /// Poll `dids` for `duration` at up to `pollRate` cycles/second. Every cycle timestamps at its
    /// start and reads each DID; unreadable DIDs are simply absent for that cycle.
    public func record(
        dids: [UInt16],
        duration: TimeInterval,
        pollRate: Double = 20,
        progress: (@Sendable (TimeInterval) -> Void)? = nil
    ) async throws -> [CapturedDID] {
        try await client.activate()
        var series: [UInt16: [TimedRaw]] = Dictionary(uniqueKeysWithValues: dids.map { ($0, []) })
        var widths: [UInt16: Int] = [:]

        let interval: UInt64 = pollRate > 0 ? UInt64(1_000_000_000 / pollRate) : 0
        let start = ContinuousClock.now
        while true {
            let elapsed = ContinuousClock.now - start
            let t = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
            if t >= duration { break }
            for did in dids {
                guard let data = try? await client.readData(did), !data.isEmpty else { continue }
                widths[did] = data.count
                series[did, default: []].append(TimedRaw(time: t, raw: Self.rawBigEndian(data)))
            }
            progress?(t)
            if Task.isCancelled { break }
            if interval > 0 { try? await Task.sleep(nanoseconds: interval) }
        }

        return dids.compactMap { did in
            let samples = series[did] ?? []
            guard !samples.isEmpty else { return nil }
            return CapturedDID(did: did, byteLength: widths[did] ?? samples.first.map { _ in 2 } ?? 2, samples: samples)
        }
    }

    /// Interpret up to the first 8 response bytes as a big-endian unsigned integer.
    static func rawBigEndian(_ bytes: [UInt8]) -> Double {
        var value: UInt64 = 0
        for byte in bytes.prefix(8) { value = (value << 8) | UInt64(byte) }
        return Double(value)
    }
}
