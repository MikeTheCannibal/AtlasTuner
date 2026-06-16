import Foundation

/// A value-transforming edit applied to a selection of cells. Operations are pure and produce
/// a new table, which keeps undo/redo trivial (snapshot the result).
public enum EditOperation: Sendable, Equatable {
    case set(Double)
    case add(Double)
    case subtract(Double)
    case multiply(Double)
    case divide(Double)
    /// Scale each cell by `(1 + percent/100)`.
    case percentChange(Double)
    /// Linearly interpolate across the selection from its edge values.
    case interpolate(InterpolationAxis)
    /// Box-average smoothing constrained to the selection; `passes` applications.
    case smooth(passes: Int)
    /// Replace every selected cell with the selection's mean.
    case flatten
    /// Paste a block of values aligned to the selection's top-left.
    case paste([[Double]])

    public var displayName: String {
        switch self {
        case .set: return "Set"
        case .add: return "Add"
        case .subtract: return "Subtract"
        case .multiply: return "Multiply"
        case .divide: return "Divide"
        case .percentChange: return "Percent Change"
        case .interpolate: return "Interpolate"
        case .smooth: return "Smooth"
        case .flatten: return "Flatten"
        case .paste: return "Paste"
        }
    }
}

public enum InterpolationAxis: Sendable, Equatable {
    case horizontal
    case vertical
    case both
}
