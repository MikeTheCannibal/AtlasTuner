import Foundation

/// Rocksoft-model CRC parameters: any width-16/32 CRC is fully described by these six values,
/// so a ROM family's exact block algorithm can be captured as data in its definition package
/// instead of code. `polynomial`, `initialValue` and `xorOut` are given in the conventional
/// (non-reflected) domain, matching published catalogues such as the CRC RevEng database.
public struct CRCParameters: Sendable, Equatable {
    public var width: Int
    public var polynomial: UInt32
    public var initialValue: UInt32
    public var xorOut: UInt32
    public var reflectInput: Bool
    public var reflectOutput: Bool

    public init(width: Int, polynomial: UInt32, initialValue: UInt32, xorOut: UInt32,
                reflectInput: Bool, reflectOutput: Bool) {
        precondition(width == 16 || width == 32, "Only CRC-16 and CRC-32 widths are supported")
        self.width = width
        self.polynomial = polynomial
        self.initialValue = initialValue
        self.xorOut = xorOut
        self.reflectInput = reflectInput
        self.reflectOutput = reflectOutput
    }

    // MARK: Presets

    /// Named parameter sets covering the algorithms seen in ECU images. Check values are the
    /// CRC of the ASCII string "123456789".
    public static let presets: [String: CRCParameters] = [
        // check 0xCBF43926 — IEEE 802.3, zlib
        "crc32": CRCParameters(width: 32, polynomial: 0x04C1_1DB7, initialValue: 0xFFFF_FFFF,
                               xorOut: 0xFFFF_FFFF, reflectInput: true, reflectOutput: true),
        // check 0xFC891918 — non-reflected variant used by several Bosch block schemes
        "crc32-bzip2": CRCParameters(width: 32, polynomial: 0x04C1_1DB7, initialValue: 0xFFFF_FFFF,
                                     xorOut: 0xFFFF_FFFF, reflectInput: false, reflectOutput: false),
        // check 0x0376E6E7
        "crc32-mpeg2": CRCParameters(width: 32, polynomial: 0x04C1_1DB7, initialValue: 0xFFFF_FFFF,
                                     xorOut: 0x0000_0000, reflectInput: false, reflectOutput: false),
        // check 0x765E7680
        "crc32-posix": CRCParameters(width: 32, polynomial: 0x04C1_1DB7, initialValue: 0x0000_0000,
                                     xorOut: 0xFFFF_FFFF, reflectInput: false, reflectOutput: false),
        // check 0x29B1
        "crc16-ccitt-false": CRCParameters(width: 16, polynomial: 0x1021, initialValue: 0xFFFF,
                                           xorOut: 0x0000, reflectInput: false, reflectOutput: false),
        // check 0xBB3D
        "crc16-arc": CRCParameters(width: 16, polynomial: 0x8005, initialValue: 0x0000,
                                   xorOut: 0x0000, reflectInput: true, reflectOutput: true),
    ]
}

/// Table-driven CRC engine for any `CRCParameters`. Supports incremental feeding so
/// multi-range checksum blocks avoid concatenating their bytes.
public struct ParametricCRC: Sendable {
    public let parameters: CRCParameters

    private let table: [UInt32]
    private let mask: UInt32
    private var crc: UInt32

    public init(_ parameters: CRCParameters) {
        self.parameters = parameters
        self.mask = parameters.width == 32 ? 0xFFFF_FFFF : (1 << parameters.width) - 1

        if parameters.reflectInput {
            let poly = Self.reflect(parameters.polynomial, width: parameters.width)
            self.table = (0..<256).map { i -> UInt32 in
                var c = UInt32(i)
                for _ in 0..<8 { c = (c & 1) != 0 ? poly ^ (c >> 1) : c >> 1 }
                return c
            }
            self.crc = Self.reflect(parameters.initialValue, width: parameters.width)
        } else {
            let poly = parameters.polynomial
            let top: UInt32 = 1 << (parameters.width - 1)
            let widthMask = mask
            self.table = (0..<256).map { i -> UInt32 in
                var c = UInt32(i) << (parameters.width - 8)
                for _ in 0..<8 { c = (c & top) != 0 ? ((c << 1) ^ poly) & widthMask : (c << 1) & widthMask }
                return c
            }
            self.crc = parameters.initialValue & mask
        }
    }

    /// Feed more bytes into the running CRC.
    public mutating func update<S: Sequence>(_ bytes: S) where S.Element == UInt8 {
        if parameters.reflectInput {
            for byte in bytes {
                crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
            }
        } else {
            let shift = parameters.width - 8
            for byte in bytes {
                crc = (table[Int(((crc >> shift) ^ UInt32(byte)) & 0xFF)] ^ (crc << 8)) & mask
            }
        }
    }

    /// The finished CRC. The engine can keep accepting `update` calls afterwards.
    public var value: UInt32 {
        var result = crc
        if parameters.reflectInput != parameters.reflectOutput {
            result = Self.reflect(result, width: parameters.width)
        }
        return (result ^ parameters.xorOut) & mask
    }

    /// One-shot convenience.
    public static func checksum<S: Sequence>(_ bytes: S, using parameters: CRCParameters) -> UInt32
    where S.Element == UInt8 {
        var engine = ParametricCRC(parameters)
        engine.update(bytes)
        return engine.value
    }

    private static func reflect(_ value: UInt32, width: Int) -> UInt32 {
        var input = value
        var output: UInt32 = 0
        for _ in 0..<width {
            output = (output << 1) | (input & 1)
            input >>= 1
        }
        return output
    }
}
