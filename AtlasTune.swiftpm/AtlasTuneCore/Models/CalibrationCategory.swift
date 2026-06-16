import Foundation

/// Top-level grouping used to organise tables in the workspace navigator.
///
/// Categories are data, not UI: the navigator renders whatever categories appear in the
/// loaded ``DefinitionPackage``. The enum captures the Phase 1 S58 taxonomy from the
/// product spec while remaining `Codable` so packages can introduce new groups.
public enum CalibrationCategory: String, Codable, Sendable, CaseIterable, Identifiable, Comparable {
    case fuel
    case ignition
    case boost
    case torque
    case safety
    case other

    public var id: String { rawValue }

    /// Human-facing title for the navigator.
    public var displayName: String {
        switch self {
        case .fuel: return "Fuel"
        case .ignition: return "Ignition"
        case .boost: return "Boost"
        case .torque: return "Torque"
        case .safety: return "Safety"
        case .other: return "Other"
        }
    }

    /// SF Symbols name suggested for the category in the navigator.
    public var symbolName: String {
        switch self {
        case .fuel: return "drop.fill"
        case .ignition: return "flame.fill"
        case .boost: return "wind"
        case .torque: return "gauge.with.dots.needle.67percent"
        case .safety: return "shield.fill"
        case .other: return "folder.fill"
        }
    }

    private var sortOrder: Int {
        CalibrationCategory.allCases.firstIndex(of: self) ?? .max
    }

    public static func < (lhs: CalibrationCategory, rhs: CalibrationCategory) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }
}

/// Optional finer-grained grouping inside a category (e.g. "Lambda Targets" under Fuel).
public struct CalibrationSubcategory: Codable, Sendable, Hashable {
    public var category: CalibrationCategory
    public var name: String

    public init(category: CalibrationCategory, name: String) {
        self.category = category
        self.name = name
    }
}
