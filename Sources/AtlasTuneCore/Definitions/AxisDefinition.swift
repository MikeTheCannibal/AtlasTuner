import Foundation

/// Describes one axis (breakpoint set) of a table.
///
/// Axis breakpoints can either be stored in the BIN (the common case — they are themselves
/// calibratable) or fixed constants baked into the definition. Either way the engine resolves
/// them to engineering values when a table is loaded.
public struct AxisDefinition: Codable, Sendable, Hashable, Identifiable {
    public enum Source: Codable, Sendable, Hashable {
        /// Breakpoints read from the image at `address` using `dataType`/`scaling`.
        case stored(address: Int, dataType: DataType, scaling: Scaling)
        /// Breakpoints are constant engineering values.
        case fixed(values: [Double])
    }

    public var id: String
    public var name: String
    public var unit: String
    /// Number of breakpoints on the axis.
    public var count: Int
    public var source: Source

    public init(id: String, name: String, unit: String, count: Int, source: Source) {
        self.id = id
        self.name = name
        self.unit = unit
        self.count = count
        self.source = source
    }

    /// Convenience for a fixed axis, inferring count from the supplied values.
    public static func fixed(id: String, name: String, unit: String, values: [Double]) -> AxisDefinition {
        AxisDefinition(id: id, name: name, unit: unit, count: values.count, source: .fixed(values: values))
    }
}
