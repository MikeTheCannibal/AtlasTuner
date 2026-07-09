import Foundation

/// The checksum layout of one ROM family, carried by its definition package so correcting a
/// family's checksums is a data problem, not a code change. Each block names the byte ranges
/// it protects, where the stored checksum lives, and the exact CRC algorithm.
public struct ChecksumScheme: Codable, Sendable, Equatable {
    public var blocks: [ChecksumBlock]

    public init(blocks: [ChecksumBlock]) {
        self.blocks = blocks
    }
}

/// One checksum-protected block. `ranges` are fed to the CRC in order, which lets a block
/// exclude the stored checksum's own bytes (the usual MG1 arrangement) by splitting around it.
public struct ChecksumBlock: Codable, Sendable, Equatable {
    public var name: String
    public var ranges: [ByteSpan]
    /// Offset of the stored checksum inside the image.
    public var storedAt: Int
    /// Byte order of the stored checksum; `nil` means the image's own order.
    public var storedByteOrder: ByteOrder?
    public var algorithm: ChecksumAlgorithm

    public init(name: String, ranges: [ByteSpan], storedAt: Int,
                storedByteOrder: ByteOrder? = nil, algorithm: ChecksumAlgorithm) {
        self.name = name
        self.ranges = ranges
        self.storedAt = storedAt
        self.storedByteOrder = storedByteOrder
        self.algorithm = algorithm
    }

    /// Storage width follows the CRC width.
    public var storedType: DataType {
        algorithm.parameters.width == 16 ? .uint16 : .uint32
    }
}

/// A contiguous byte range, JSON-friendly.
public struct ByteSpan: Codable, Sendable, Equatable {
    public var start: Int
    public var length: Int

    public init(start: Int, length: Int) {
        self.start = start
        self.length = length
    }

    public var range: Range<Int> { start..<(start + length) }
}

/// Either a named preset from `CRCParameters.presets` or explicit Rocksoft parameters.
/// JSON forms:
///   {"preset": "crc32"}
///   {"width": 32, "polynomial": "0x04C11DB7", "initialValue": "0xFFFFFFFF",
///    "xorOut": "0xFFFFFFFF", "reflectInput": true, "reflectOutput": true}
/// Numeric fields accept a JSON number or a hex string.
public enum ChecksumAlgorithm: Sendable, Equatable {
    case preset(String)
    case custom(CRCParameters)

    /// The resolved parameter set. An unknown preset name resolves to standard CRC-32 —
    /// decoding validates names, so this only guards hand-constructed values.
    public var parameters: CRCParameters {
        switch self {
        case .preset(let name):
            return CRCParameters.presets[name] ?? CRCParameters.presets["crc32"]!
        case .custom(let parameters):
            return parameters
        }
    }
}

extension ChecksumAlgorithm: Codable {
    private enum CodingKeys: String, CodingKey {
        case preset, width, polynomial, initialValue, xorOut, reflectInput, reflectOutput
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let name = try container.decodeIfPresent(String.self, forKey: .preset) {
            guard CRCParameters.presets[name] != nil else {
                throw DecodingError.dataCorruptedError(
                    forKey: .preset, in: container,
                    debugDescription: "Unknown checksum preset ‘\(name)’. Known presets: \(CRCParameters.presets.keys.sorted().joined(separator: ", "))."
                )
            }
            self = .preset(name)
        } else {
            self = .custom(CRCParameters(
                width: try container.decode(Int.self, forKey: .width),
                polynomial: try Self.word(container, .polynomial),
                initialValue: try Self.word(container, .initialValue),
                xorOut: try Self.word(container, .xorOut),
                reflectInput: try container.decode(Bool.self, forKey: .reflectInput),
                reflectOutput: try container.decode(Bool.self, forKey: .reflectOutput)
            ))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .preset(let name):
            try container.encode(name, forKey: .preset)
        case .custom(let p):
            try container.encode(p.width, forKey: .width)
            try container.encode(p.polynomial, forKey: .polynomial)
            try container.encode(p.initialValue, forKey: .initialValue)
            try container.encode(p.xorOut, forKey: .xorOut)
            try container.encode(p.reflectInput, forKey: .reflectInput)
            try container.encode(p.reflectOutput, forKey: .reflectOutput)
        }
    }

    /// Decode a UInt32 given as a JSON number or a "0x…" hex string.
    private static func word(_ container: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) throws -> UInt32 {
        if let number = try? container.decode(UInt32.self, forKey: key) { return number }
        let text = try container.decode(String.self, forKey: key)
        let digits = text.hasPrefix("0x") || text.hasPrefix("0X") ? String(text.dropFirst(2)) : text
        guard let value = UInt32(digits, radix: 16) else {
            throw DecodingError.dataCorruptedError(
                forKey: key, in: container,
                debugDescription: "Expected a number or hex string for \(key.stringValue), got ‘\(text)’."
            )
        }
        return value
    }
}
