import Foundation

/// Errors surfaced by low-level BIN access.
public enum BINError: Error, Equatable, Sendable {
    case outOfBounds(offset: Int, length: Int, imageSize: Int)
    case unsupportedConversion
}

/// An in-memory ECU image with typed, endianness-aware read/write access.
///
/// `BINImage` is a value type backed by `Data`. Mutations are copy-on-write, which keeps
/// revision snapshots cheap until a write actually diverges them. All multi-byte access
/// honours the image's ``ByteOrder``.
public struct BINImage: Sendable, Equatable {
    public private(set) var bytes: Data
    public var byteOrder: ByteOrder

    public init(bytes: Data, byteOrder: ByteOrder = .littleEndian) {
        self.bytes = bytes
        self.byteOrder = byteOrder
    }

    public var size: Int { bytes.count }

    // MARK: Bounds

    @inline(__always)
    private func checkRange(_ offset: Int, _ length: Int) throws {
        guard offset >= 0, length >= 0, offset + length <= bytes.count else {
            throw BINError.outOfBounds(offset: offset, length: length, imageSize: bytes.count)
        }
    }

    /// Read `length` raw bytes starting at `offset`.
    public func readBytes(at offset: Int, length: Int) throws -> [UInt8] {
        try checkRange(offset, length)
        let start = bytes.startIndex + offset
        return Array(bytes[start..<(start + length)])
    }

    /// Overwrite bytes starting at `offset`.
    public mutating func writeBytes(_ newBytes: [UInt8], at offset: Int) throws {
        try checkRange(offset, newBytes.count)
        let start = bytes.startIndex + offset
        bytes.replaceSubrange(start..<(start + newBytes.count), with: newBytes)
    }

    // MARK: Raw numeric reads

    /// Read a single value of `type` at `offset` as a `Double` raw value (before scaling).
    public func readRaw(_ type: DataType, at offset: Int) throws -> Double {
        let raw = try readBytes(at: offset, length: type.byteWidth)
        let ordered = byteOrder == .littleEndian ? raw : Array(raw.reversed())
        return Self.decode(type, littleEndianBytes: ordered)
    }

    /// Write a `Double` raw value of `type` at `offset`, rounding for integer types.
    public mutating func writeRaw(_ value: Double, type: DataType, at offset: Int) throws {
        let le = Self.encode(type, raw: value)
        let ordered = byteOrder == .littleEndian ? le : Array(le.reversed())
        try writeBytes(ordered, at: offset)
    }

    // MARK: Encode / decode helpers (little-endian input/output)

    static func decode(_ type: DataType, littleEndianBytes b: [UInt8]) -> Double {
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

    static func encode(_ type: DataType, raw: Double) -> [UInt8] {
        func bytes<T: FixedWidthInteger>(_ v: T) -> [UInt8] {
            (0..<MemoryLayout<T>.size).map { UInt8(truncatingIfNeeded: v >> (8 * $0)) }
        }
        switch type {
        case .uint8:
            return [UInt8(clampInt(raw, 0, Double(UInt8.max)))]
        case .int8:
            return [UInt8(bitPattern: Int8(clampInt(raw, Double(Int8.min), Double(Int8.max))))]
        case .uint16:
            return bytes(UInt16(clampInt(raw, 0, Double(UInt16.max))))
        case .int16:
            return bytes(UInt16(bitPattern: Int16(clampInt(raw, Double(Int16.min), Double(Int16.max)))))
        case .uint32:
            return bytes(UInt32(clampInt(raw, 0, Double(UInt32.max))))
        case .int32:
            return bytes(UInt32(bitPattern: Int32(clampInt(raw, Double(Int32.min), Double(Int32.max)))))
        case .float32:
            return bytes(Float(raw).bitPattern)
        }
    }

    private static func clampInt(_ v: Double, _ lo: Double, _ hi: Double) -> Int64 {
        Int64(min(max(v.rounded(), lo), hi))
    }
}
