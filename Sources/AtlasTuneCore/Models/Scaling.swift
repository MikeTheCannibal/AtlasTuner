import Foundation

/// Converts between the raw integer/float stored in a BIN and the engineering value
/// shown to the tuner, using a linear transform: `display = raw * factor + offset`.
///
/// Linear scaling covers the overwhelming majority of BMW MG1 calibration tables.
/// More exotic transforms can be modelled by future conforming types behind the
/// ``ValueTransform`` protocol without changing call sites.
public struct Scaling: Codable, Sendable, Hashable, ValueTransform {
    public var factor: Double
    public var offset: Double
    /// Number of decimal places to present in the UI. Does not affect stored precision.
    public var decimals: Int

    public init(factor: Double = 1.0, offset: Double = 0.0, decimals: Int = 2) {
        self.factor = factor
        self.offset = offset
        self.decimals = decimals
    }

    /// Identity scaling (raw == display).
    public static let identity = Scaling(factor: 1.0, offset: 0.0, decimals: 0)

    public func display(fromRaw raw: Double) -> Double {
        raw * factor + offset
    }

    public func raw(fromDisplay display: Double) -> Double {
        guard factor != 0 else { return 0 }
        return (display - offset) / factor
    }
}

/// Abstraction over a raw <-> engineering value transform so that tables are not
/// hard-wired to linear scaling.
public protocol ValueTransform: Sendable {
    func display(fromRaw raw: Double) -> Double
    func raw(fromDisplay display: Double) -> Double
}
