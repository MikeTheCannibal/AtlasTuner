import Foundation

/// The raw numeric encoding of a value stored inside a BIN image.
///
/// A `DataType` describes only how bytes are laid out — the conversion to a
/// human-readable engineering value (e.g. degrees of timing, lambda) is the
/// responsibility of ``Scaling``.
public enum DataType: String, Codable, Sendable, CaseIterable {
    case uint8
    case int8
    case uint16
    case int16
    case uint32
    case int32
    case float32

    /// Number of bytes a single value of this type occupies.
    public var byteWidth: Int {
        switch self {
        case .uint8, .int8: return 1
        case .uint16, .int16: return 2
        case .uint32, .int32, .float32: return 4
        }
    }

    /// Whether the type can represent negative numbers.
    public var isSigned: Bool {
        switch self {
        case .int8, .int16, .int32, .float32: return true
        case .uint8, .uint16, .uint32: return false
        }
    }

    /// The inclusive range of raw values representable by an integer type.
    /// Returns `nil` for `float32`, whose range is effectively unbounded for clamping purposes.
    public var rawRange: ClosedRange<Double>? {
        switch self {
        case .uint8: return 0...Double(UInt8.max)
        case .int8: return Double(Int8.min)...Double(Int8.max)
        case .uint16: return 0...Double(UInt16.max)
        case .int16: return Double(Int16.min)...Double(Int16.max)
        case .uint32: return 0...Double(UInt32.max)
        case .int32: return Double(Int32.min)...Double(Int32.max)
        case .float32: return nil
        }
    }
}
