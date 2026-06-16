import Foundation

/// Endianness used when reading and writing multi-byte values from a `BINImage`.
///
/// BMW MG1 (Infineon AURIX TriCore) calibration regions are little-endian, which is
/// the default throughout Atlas Tune. The value is kept configurable so that the same
/// engine can support big-endian ROM families in later phases without code changes.
public enum ByteOrder: String, Codable, Sendable, CaseIterable {
    case littleEndian
    case bigEndian

    /// The native byte order of the host running the engine.
    public static var host: ByteOrder {
        let probe: UInt16 = 0x0102
        return withUnsafeBytes(of: probe) { $0.first == 0x02 ? .littleEndian : .bigEndian }
    }
}
