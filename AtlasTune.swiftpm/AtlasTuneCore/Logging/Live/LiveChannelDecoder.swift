import Foundation

/// Decodes a UDS positive response into the engineering value for its channel, applying the DID's
/// data type, byte order and scaling. Pure and byte-exact, so it is fully testable without a car.
public struct LiveChannelDecoder: Sendable {
    public init() {}

    /// Decode the value carried by `identifier` from the `data` portion of its positive response
    /// (the bytes after the `0x62`+DID echo). Returns `nil` if the response is too short.
    public func value(_ identifier: UDSDataIdentifier, from data: [UInt8]) -> Double? {
        let width = identifier.dataType.byteWidth
        let start = identifier.byteOffset
        guard start >= 0, start + width <= data.count else { return nil }
        let slice = Array(data[start..<(start + width)])
        let ordered = identifier.byteOrder == .littleEndian ? slice : slice.reversed()
        let raw = Self.rawValue(identifier.dataType, littleEndianBytes: Array(ordered))
        return identifier.scaling.display(fromRaw: raw)
    }

    /// Decode a raw numeric value from little-endian-ordered bytes.
    static func rawValue(_ type: DataType, littleEndianBytes b: [UInt8]) -> Double {
        func u<T: FixedWidthInteger>(_ t: T.Type) -> T {
            var v: T = 0
            for i in 0..<b.count { v |= T(b[i]) << (8 * i) }
            return v
        }
        switch type {
        case .uint8: return Double(b[0])
        case .int8: return Double(Int8(bitPattern: b[0]))
        case .uint16: return Double(u(UInt16.self))
        case .int16: return Double(Int16(bitPattern: u(UInt16.self)))
        case .uint32: return Double(u(UInt32.self))
        case .int32: return Double(Int32(bitPattern: u(UInt32.self)))
        case .float32: return Double(Float(bitPattern: u(UInt32.self)))
        }
    }
}
