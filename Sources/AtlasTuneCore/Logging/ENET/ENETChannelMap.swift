import Foundation

/// Decodes one channel out of a UDS data-identifier response: which DID to read, where the value
/// sits in the response bytes, and how to scale it. UDS payloads are big-endian (Motorola order).
public struct ENETSignal: Sendable {
    public let channel: LogChannel
    public let did: UInt16
    public let byteOffset: Int
    public let dataType: DataType
    public let scaling: Scaling

    public init(channel: LogChannel, did: UInt16, byteOffset: Int, dataType: DataType, scaling: Scaling) {
        self.channel = channel
        self.did = did
        self.byteOffset = byteOffset
        self.dataType = dataType
        self.scaling = scaling
    }
}

/// Maps a set of UDS data identifiers to the channels they contain, for a given tester/ECU
/// address pair. This is the configurable bridge between the protocol and the logging UI.
public struct ENETChannelMap: Sendable {
    /// Tester (client) logical address. 0x0E00 is the common external-tester address.
    public var testerAddress: UInt16
    /// Target ECU logical address. The S58 DME is typically 0x0010 / 0x1000-range.
    public var ecuAddress: UInt16
    public var signals: [ENETSignal]

    public init(testerAddress: UInt16, ecuAddress: UInt16, signals: [ENETSignal]) {
        self.testerAddress = testerAddress
        self.ecuAddress = ecuAddress
        self.signals = signals
    }

    /// The distinct DIDs that must be polled each cycle.
    public var dids: [UInt16] { Array(Set(signals.map(\.did))).sorted() }

    /// Channels exposed by this map, in signal order.
    public var channels: [LogChannel] {
        var seen = Set<String>()
        return signals.compactMap { seen.insert($0.channel.id).inserted ? $0.channel : nil }
    }
}

/// Turns a set of DID responses into a `LogSample` using a channel map.
public struct ENETDecoder: Sendable {
    public let map: ENETChannelMap
    public init(map: ENETChannelMap) { self.map = map }

    /// Decode all signals whose DID is present in `responses` (raw UDS data bytes per DID).
    public func sample(time: TimeInterval, responses: [UInt16: [UInt8]]) -> LogSample {
        var values: [String: Double] = [:]
        for signal in map.signals {
            guard let bytes = responses[signal.did] else { continue }
            let image = BINImage(bytes: Data(bytes), byteOrder: .bigEndian)
            if let raw = try? image.readRaw(signal.dataType, at: signal.byteOffset) {
                values[signal.channel.id] = signal.scaling.display(fromRaw: raw)
            }
        }
        return LogSample(time: time, values: values)
    }
}

public extension ENETChannelMap {
    /// A PLACEHOLDER S58/MG1CS049 logging map.
    ///
    /// The DoIP/UDS framing and transport are real, but the data identifiers and byte layouts below
    /// are illustrative — BMW's live-logging DIDs/addresses for the S58 are not published. Replace
    /// these with verified values (and confirm the tester/ECU addresses) before expecting real
    /// channel data on the vehicle. Until then this maps the pipeline end-to-end so the transport
    /// can be exercised.
    static let s58Placeholder = ENETChannelMap(
        testerAddress: 0x0E00,
        ecuAddress: 0x0010,
        signals: [
            ENETSignal(channel: .rpm, did: 0xF40C, byteOffset: 0, dataType: .uint16,
                       scaling: Scaling(factor: 0.25, offset: 0, decimals: 0)),
            ENETSignal(channel: .load, did: 0xF441, byteOffset: 0, dataType: .uint16,
                       scaling: Scaling(factor: 0.01, offset: 0, decimals: 1)),
            ENETSignal(channel: .boost, did: 0x4B01, byteOffset: 0, dataType: .uint16,
                       scaling: Scaling(factor: 0.01, offset: 0, decimals: 2)),
            ENETSignal(channel: .lambda, did: 0x4C01, byteOffset: 0, dataType: .uint16,
                       scaling: Scaling(factor: 0.0001, offset: 0, decimals: 3)),
            ENETSignal(channel: .ignitionTiming, did: 0x4D01, byteOffset: 0, dataType: .int16,
                       scaling: Scaling(factor: 0.1, offset: 0, decimals: 1)),
            ENETSignal(channel: .knock, did: 0x4E01, byteOffset: 0, dataType: .int16,
                       scaling: Scaling(factor: 0.1, offset: 0, decimals: 1)),
            ENETSignal(channel: .iat, did: 0xF446, byteOffset: 0, dataType: .uint8,
                       scaling: Scaling(factor: 1, offset: -40, decimals: 0)),
            ENETSignal(channel: .coolant, did: 0xF405, byteOffset: 0, dataType: .uint8,
                       scaling: Scaling(factor: 1, offset: -40, decimals: 0)),
        ]
    )
}
