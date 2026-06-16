import Foundation

/// Phase 1 definition package for the BMW S58 (G87 M2 / MG1CS049, DME 8.6.S family).
///
/// Identification (image size + byte signatures + version banner) is reconciled against a real
/// G87 M2 image: an 8 MB MG1CS049 dump reporting `DME8.6.S_S58_G87` with calibration
/// `CB_011_253.23.0_1.2.0`.
///
/// Tables are laid out contiguously from `baseAddress` by a small builder so the structural
/// addresses stay internally consistent. As stated in `S58Axes`, the table *value* offsets are
/// still placeholders pending reconciliation with a verified S58 map — the point of this file is
/// the data-driven shape of the package, not the literal table byte positions.
public enum S58DefinitionPackage {

    /// Full MG1CS049 image size in bytes (8 MiB), used for size-based identification gating.
    public static let imageSize = 8 * 1024 * 1024

    public static func make() -> DefinitionPackage {
        var builder = TableBuilder(baseAddress: 0x10000)

        let tables: [TableDefinition] = [
            // MARK: Fuel
            builder.map3D(id: "fuel.lambda", name: "Lambda Targets", category: .fuel,
                          subcategory: "Lambda Targets", unit: "λ",
                          scaling: Scaling(factor: 0.0010, offset: 0, decimals: 3),
                          x: S58Axes.rpm, y: S58Axes.load, range: 0.60...1.20,
                          description: "Commanded air/fuel ratio (lambda) vs load and engine speed."),
            builder.map2D(id: "fuel.comp.iat", name: "Fuel Compensation (IAT)", category: .fuel,
                          subcategory: "Fuel Compensation", unit: "%",
                          scaling: Scaling(factor: 0.1, offset: -12.8, decimals: 1),
                          x: S58Axes.rpm, y: S58Axes.iat, range: (-25)...25,
                          description: "Fuel quantity trim vs intake air temperature."),
            builder.map1D(id: "fuel.scalar", name: "Injector Scalar", category: .fuel,
                          subcategory: "Fuel Scalars", unit: "cc/min",
                          scaling: Scaling(factor: 0.1, offset: 0, decimals: 1),
                          x: S58Axes.rpm, range: 0...2000,
                          description: "Effective injector flow scalar vs engine speed."),

            // MARK: Ignition
            builder.map3D(id: "ign.base", name: "Base Timing", category: .ignition,
                          subcategory: "Base Timing", unit: "°",
                          scaling: Scaling(factor: 0.1, offset: -10, decimals: 1),
                          x: S58Axes.rpm, y: S58Axes.load, range: (-10)...45,
                          description: "Base ignition advance vs load and engine speed."),
            builder.map2D(id: "ign.comp.iat", name: "Timing Compensation (IAT)", category: .ignition,
                          subcategory: "Timing Compensation", unit: "°",
                          scaling: Scaling(factor: 0.1, offset: -12.8, decimals: 1),
                          x: S58Axes.rpm, y: S58Axes.iat, range: (-15)...5,
                          description: "Ignition advance trim vs intake air temperature."),
            builder.map3D(id: "ign.knock", name: "Knock Threshold", category: .ignition,
                          subcategory: "Knock Related Tables", unit: "°",
                          scaling: Scaling(factor: 0.1, offset: 0, decimals: 1),
                          x: S58Axes.rpm, y: S58Axes.load, range: 0...20,
                          description: "Maximum knock-based timing retract vs load and engine speed."),

            // MARK: Boost
            builder.map3D(id: "boost.target", name: "Boost Targets", category: .boost,
                          subcategory: "Boost Targets", unit: "psi",
                          scaling: Scaling(factor: 0.01, offset: 0, decimals: 2),
                          x: S58Axes.rpm, y: S58Axes.load, range: 0...35,
                          description: "Target manifold boost pressure vs load and engine speed."),
            builder.map3D(id: "boost.wgdc", name: "Wastegate Base Duty", category: .boost,
                          subcategory: "Wastegate Tables", unit: "%",
                          scaling: Scaling(factor: 0.1, offset: 0, decimals: 1),
                          x: S58Axes.rpm, y: S58Axes.load, range: 0...100,
                          description: "Base wastegate duty cycle vs load and engine speed."),
            builder.map1D(id: "boost.loadtarget", name: "Load Targets", category: .boost,
                          subcategory: "Load Targets", unit: "%",
                          scaling: Scaling(factor: 0.1, offset: 0, decimals: 1),
                          x: S58Axes.rpm, range: 0...260,
                          description: "Requested engine load ceiling vs engine speed."),

            // MARK: Torque
            builder.map3D(id: "torque.demand", name: "Driver Demand", category: .torque,
                          subcategory: "Driver Demand", unit: "Nm",
                          scaling: Scaling(factor: 1.0, offset: 0, decimals: 0),
                          x: S58Axes.rpm, y: S58Axes.load, range: 0...750,
                          description: "Driver-requested torque vs pedal and engine speed."),
            builder.map1D(id: "torque.limit", name: "Torque Limiter", category: .torque,
                          subcategory: "Torque Limiters", unit: "Nm",
                          scaling: Scaling(factor: 1.0, offset: 0, decimals: 0),
                          x: S58Axes.rpm, range: 0...800,
                          description: "Maximum allowed torque vs engine speed."),

            // MARK: Safety
            builder.map1D(id: "safety.tempprot", name: "Temperature Protection", category: .safety,
                          subcategory: "Temperature Protection", unit: "%",
                          scaling: Scaling(factor: 0.1, offset: 0, decimals: 1),
                          x: S58Axes.coolant, range: 0...100,
                          description: "Power reduction vs coolant temperature."),
            builder.map1D(id: "safety.torqueprot", name: "Torque Protection", category: .safety,
                          subcategory: "Torque Protection", unit: "Nm",
                          scaling: Scaling(factor: 1.0, offset: 0, decimals: 0),
                          x: S58Axes.rpm, range: 0...800,
                          description: "Hard torque ceiling vs engine speed."),
            builder.map2D(id: "safety.comp.ect", name: "Coolant Compensation", category: .safety,
                          subcategory: "Compensation Tables", unit: "°",
                          scaling: Scaling(factor: 0.1, offset: -12.8, decimals: 1),
                          x: S58Axes.rpm, y: S58Axes.coolant, range: (-15)...5,
                          description: "Ignition trim vs coolant temperature."),
        ]

        return DefinitionPackage(
            id: "bmw.s58.mg1cs049.cb011",
            family: "S58 / MG1CS049 (DME 8.6.S)",
            calibrationVersion: "CB_011_253.23.0_1.2.0",
            expectedImageSizes: [imageSize],
            // Calibration banner near the start of the cal region.
            versionField: VersionField(address: 0x29000, length: 21),
            signatures: [
                // DME build descriptor (integration level I35UP) at a fixed offset.
                ROMSignature(address: 0x5FE1E, ascii: "#DME_86T0#CX#BTL#MDG1_I35UP",
                             label: "MG1CS049 build descriptor"),
                // Strong S58/G87 family marker in the trailing DME identification block.
                ROMSignature(address: 0x7FFE51, ascii: "DME8.6.S_S58_G87",
                             label: "DME 8.6.S S58 G87 marker"),
            ],
            tables: tables
        )
    }
}

/// Lays out tables sequentially, advancing a cursor by each table's byte size. Axes here are
/// fixed (constant) so they consume no image space.
private struct TableBuilder {
    private(set) var cursor: Int

    init(baseAddress: Int) { self.cursor = baseAddress }

    mutating func map1D(id: String, name: String, category: CalibrationCategory, subcategory: String,
                        unit: String, scaling: Scaling, x: AxisDefinition,
                        range: ClosedRange<Double>, description: String) -> TableDefinition {
        let def = TableDefinition(id: id, name: name, description: description, category: category,
                                  subcategory: subcategory, address: cursor, dataType: .uint16,
                                  scaling: scaling, unit: unit, rows: 1, columns: x.count,
                                  xAxis: x, yAxis: nil, valueRange: range)
        cursor += def.byteSize
        return def
    }

    mutating func map2D(id: String, name: String, category: CalibrationCategory, subcategory: String,
                        unit: String, scaling: Scaling, x: AxisDefinition, y: AxisDefinition,
                        range: ClosedRange<Double>, description: String) -> TableDefinition {
        map3D(id: id, name: name, category: category, subcategory: subcategory, unit: unit,
              scaling: scaling, x: x, y: y, range: range, description: description)
    }

    mutating func map3D(id: String, name: String, category: CalibrationCategory, subcategory: String,
                        unit: String, scaling: Scaling, x: AxisDefinition, y: AxisDefinition,
                        range: ClosedRange<Double>, description: String) -> TableDefinition {
        let def = TableDefinition(id: id, name: name, description: description, category: category,
                                  subcategory: subcategory, address: cursor, dataType: .uint16,
                                  scaling: scaling, unit: unit, rows: y.count, columns: x.count,
                                  xAxis: x, yAxis: y, valueRange: range)
        cursor += def.byteSize
        return def
    }
}
