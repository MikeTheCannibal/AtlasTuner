import Foundation

/// Shared axis breakpoint sets for the BMW S58 (MG1CS003) Phase 1 definition.
///
/// Breakpoint *values* below reflect typical S58 operating ranges. Where an axis is stored in
/// the BIN it is modelled as `.stored`; fixed axes are used where breakpoints are constants.
///
/// NOTE: addresses in this package are structural placeholders for the engine and MUST be
/// reconciled against a verified S58 map before any real calibration work. The architecture is
/// data-driven precisely so these values can be corrected without code changes.
public enum S58Axes {
    /// Engine speed breakpoints (rpm), used as the X axis on most 3D maps.
    public static let rpm = AxisDefinition.fixed(
        id: "axis.rpm", name: "Engine Speed", unit: "rpm",
        values: [800, 1200, 1600, 2000, 2500, 3000, 3500, 4000, 4500, 5000, 5500, 6000, 6500, 7000, 7200]
    )

    /// Load / requested torque breakpoints (%), used as the Y axis on fuel & ignition maps.
    public static let load = AxisDefinition.fixed(
        id: "axis.load", name: "Engine Load", unit: "%",
        values: [10, 20, 30, 40, 50, 60, 70, 80, 90, 100, 120, 140, 160, 180, 200]
    )

    /// Intake air temperature breakpoints (°C) for compensation tables.
    public static let iat = AxisDefinition.fixed(
        id: "axis.iat", name: "Intake Air Temp", unit: "°C",
        values: [-20, 0, 20, 30, 40, 50, 60, 70]
    )

    /// Coolant temperature breakpoints (°C).
    public static let coolant = AxisDefinition.fixed(
        id: "axis.ect", name: "Coolant Temp", unit: "°C",
        values: [-20, 0, 20, 40, 60, 80, 100, 110]
    )
}
