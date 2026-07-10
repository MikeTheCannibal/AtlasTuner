import Foundation

/// A UDS (ISO 14229) `ReadDataByIdentifier` channel: a 16-bit data identifier plus how to turn the
/// raw bytes at a given offset in the response into an engineering value for a ``LogChannel``.
///
/// Live logging polls a set of these. Rather than hard-code BMW's DID map, definitions supply them
/// as data — the same data-driven philosophy as the table definitions — so a new ROM family is a
/// data change, not a code change.
public struct UDSDataIdentifier: Codable, Sendable, Equatable, Identifiable {
    /// The `LogChannel` this DID feeds. `id` is the channel id for stable identity.
    public var channel: LogChannel
    /// The 16-bit UDS data identifier (e.g. 0xF40C for engine speed on many BMWs).
    public var did: UInt16
    /// Byte offset of this value within the DID's data (after the 3-byte 0x62 + DID echo header).
    public var byteOffset: Int
    /// Raw encoding of the value at `byteOffset`.
    public var dataType: DataType
    /// Byte order of the raw value. DoIP/UDS payloads are big-endian by convention.
    public var byteOrder: ByteOrder
    /// Linear scaling from raw to engineering units.
    public var scaling: Scaling

    public var id: String { channel.id }

    public init(channel: LogChannel, did: UInt16, byteOffset: Int = 0,
                dataType: DataType = .uint16, byteOrder: ByteOrder = .bigEndian,
                scaling: Scaling = .identity) {
        self.channel = channel
        self.did = did
        self.byteOffset = byteOffset
        self.dataType = dataType
        self.byteOrder = byteOrder
        self.scaling = scaling
    }

    /// Total bytes this reader needs after the DID header.
    public var byteWidth: Int { byteOffset + dataType.byteWidth }
}

/// A named collection of DIDs to poll for a ROM family, carried by the definition layer.
public struct LiveChannelSet: Codable, Sendable, Equatable {
    public var identifiers: [UDSDataIdentifier]

    public init(identifiers: [UDSDataIdentifier]) {
        self.identifiers = identifiers
    }

    public var channels: [LogChannel] { identifiers.map(\.channel) }

    /// A conservative S58 starter set. DIDs here are placeholders to be confirmed against a real
    /// vehicle/ODX before shipping — the point is that they are *data*, changed without code edits.
    public static let s58Placeholder = LiveChannelSet(identifiers: [
        UDSDataIdentifier(channel: .rpm, did: 0xF40C, dataType: .uint16,
                          scaling: Scaling(factor: 0.25, decimals: 0)),
        UDSDataIdentifier(channel: .load, did: 0xF404, dataType: .uint8,
                          scaling: Scaling(factor: 100.0 / 255.0, decimals: 1)),
        UDSDataIdentifier(channel: .boost, did: 0xF40B, dataType: .uint16,
                          scaling: Scaling(factor: 0.0145, offset: -14.7, decimals: 2)),
        UDSDataIdentifier(channel: .lambda, did: 0xF444, dataType: .uint16,
                          scaling: Scaling(factor: 0.0001, decimals: 3)),
        UDSDataIdentifier(channel: .iat, did: 0xF40F, dataType: .uint8,
                          scaling: Scaling(factor: 1, offset: -40, decimals: 0)),
        UDSDataIdentifier(channel: .coolant, did: 0xF405, dataType: .uint8,
                          scaling: Scaling(factor: 1, offset: -40, decimals: 0)),
    ])
}
