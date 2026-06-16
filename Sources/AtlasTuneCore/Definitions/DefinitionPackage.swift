import Foundation

/// A self-contained, data-driven description of one ROM family/version: how to recognise it
/// and every table it exposes. Loading the right package is what turns an anonymous blob of
/// bytes into an editable calibration.
public struct DefinitionPackage: Codable, Sendable, Identifiable {
    public var id: String
    /// ROM family label, e.g. "S58 / MG1CS003".
    public var family: String
    /// Calibration/software version this package targets.
    public var calibrationVersion: String
    /// Image sizes (in bytes) this package is valid for.
    public var expectedImageSizes: [Int]
    /// Optional location of a printable version banner inside the image.
    public var versionField: VersionField?
    /// Byte patterns used to identify the family.
    public var signatures: [ROMSignature]
    /// Every table defined for this ROM.
    public var tables: [TableDefinition]

    public init(
        id: String,
        family: String,
        calibrationVersion: String,
        expectedImageSizes: [Int],
        versionField: VersionField? = nil,
        signatures: [ROMSignature] = [],
        tables: [TableDefinition] = []
    ) {
        self.id = id
        self.family = family
        self.calibrationVersion = calibrationVersion
        self.expectedImageSizes = expectedImageSizes
        self.versionField = versionField
        self.signatures = signatures
        self.tables = tables
    }

    // MARK: Lookups

    public func table(id: String) -> TableDefinition? {
        tables.first { $0.id == id }
    }

    public func tables(in category: CalibrationCategory) -> [TableDefinition] {
        tables.filter { $0.category == category }.sorted { $0.name < $1.name }
    }

    /// Categories present in this package, in canonical order.
    public var categories: [CalibrationCategory] {
        let present = Set(tables.map(\.category))
        return CalibrationCategory.allCases.filter(present.contains)
    }
}
