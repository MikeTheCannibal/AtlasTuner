import Foundation

/// One responding data identifier found by a scan: its id, the byte length of the response, and a
/// sample of the raw bytes. Read-only reconnaissance — the scan only ever issues `ReadDataByIdentifier`.
public struct DIDProbe: Sendable, Equatable, Identifiable {
    public let did: UInt16
    public let byteLength: Int
    public let sample: [UInt8]
    public var id: UInt16 { did }

    public init(did: UInt16, byteLength: Int, sample: [UInt8]) {
        self.did = did
        self.byteLength = byteLength
        self.sample = sample
    }
}

/// Sweeps a range of UDS data identifiers over a live DoIP session to discover which ones the ECU
/// answers, and how wide each response is. This is the first, car-side step of reconciling the S58
/// DID map: it never writes anything (only service 0x22), so it is safe to run with the engine
/// running or key-on. Feed the responders it finds to ``DIDCapture`` for a timed recording.
public actor DIDScanner {
    private let client: DoIPClient

    public init(client: DoIPClient) {
        self.client = client
    }

    /// Activate the session and probe every DID in `range`. Identifiers that answer with data are
    /// returned; those that reject (`requestOutOfRange`) or time out are skipped. `progress` is
    /// called after each probe with the DID just tried and the running count of responders.
    public func scan(
        range: ClosedRange<UInt16>,
        progress: (@Sendable (UInt16, Int) -> Void)? = nil
    ) async throws -> [DIDProbe] {
        try await client.activate()
        var probes: [DIDProbe] = []
        var did = range.lowerBound
        while true {
            if let data = try? await client.readData(did), !data.isEmpty {
                probes.append(DIDProbe(did: did, byteLength: data.count, sample: data))
            }
            progress?(did, probes.count)
            if did == range.upperBound { break }
            did += 1
        }
        return probes
    }
}
