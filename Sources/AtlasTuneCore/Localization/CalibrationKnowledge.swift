import Foundation

/// A plain-English explanation of what a calibration table does and why it matters for the tune.
public struct CalibrationInsight: Sendable, Equatable {
    /// What the table represents.
    public let summary: String
    /// Why a tuner cares about it on the S58 specifically.
    public let tuningNote: String

    public init(summary: String, tuningNote: String) {
        self.summary = summary
        self.tuningNote = tuningNote
    }
}

/// A curated, keyword-driven knowledge base that explains S58 calibration tables to a regular
/// user. It does not need the internet: it matches the (optionally English-translated) table name,
/// subcategory and unit against concept entries. A "look it up online" affordance in the UI
/// complements this for anything not covered.
public struct CalibrationKnowledge: Sendable {
    public static let shared = CalibrationKnowledge()
    public init() {}

    private struct Entry { let keywords: [String]; let insight: CalibrationInsight }

    /// Best concept match for a table. Pass the English `name` when translation is enabled so the
    /// German originals still match the keyword list.
    public func insight(name: String, subcategory: String?, category: CalibrationCategory, unit: String) -> CalibrationInsight {
        let haystack = "\(name) \(subcategory ?? "") \(unit)".lowercased()
        for entry in Self.entries where entry.keywords.contains(where: haystack.contains) {
            return entry.insight
        }
        return Self.categoryFallback(category)
    }

    // MARK: Concept library

    private static let entries: [Entry] = [
        Entry(keywords: ["lambda", "afr", "air/fuel", "air fuel", "mixture", "gemisch"],
              insight: CalibrationInsight(
                summary: "Commanded air/fuel ratio (lambda) the ECU targets across load and RPM.",
                tuningNote: "On the S58, richer (lower lambda) under boost lowers EGTs and knock risk at the cost of fuel; the component-protection lambda enrichment is a key safety lever.")),
        Entry(keywords: ["boost", "ladedruck", "manifold pressure", "saugrohr", "charge pressure"],
              insight: CalibrationInsight(
                summary: "Target boost / manifold pressure the turbos are asked to deliver.",
                tuningNote: "The headline power lever on the S58's twin turbos. Raise carefully alongside fueling, timing and the torque/load limiters or the ECU will pull it back.")),
        Entry(keywords: ["wastegate", "wgdc", "duty"],
              insight: CalibrationInsight(
                summary: "Wastegate duty cycle — how far the wastegates are held closed to build boost.",
                tuningNote: "Feed-forward base for the boost controller. Too high causes overshoot/spikes; the closed-loop PID trims around this base.")),
        Entry(keywords: ["timing", "ignition", "zünd", "zuend", "spark", "beginnwinkel", "advance"],
              insight: CalibrationInsight(
                summary: "Ignition advance (degrees BTDC) versus load and RPM.",
                tuningNote: "More advance makes power until knock appears. The S58 is knock-limited up top, so timing is trimmed by the knock system and IAT/coolant compensations.")),
        Entry(keywords: ["knock", "klopf"],
              insight: CalibrationInsight(
                summary: "Knock detection thresholds and the timing retard applied when knock is sensed.",
                tuningNote: "Defines how aggressively the ECU pulls timing. Logging knock activity against these tables shows where the calibration is on the edge.")),
        Entry(keywords: ["wgdc", "pid", "regler", "controller", "i-anteil", "p-anteil", "d-factor", "p-factor", "i-factor"],
              insight: CalibrationInsight(
                summary: "Closed-loop controller gains (P/I/D) for a regulated quantity such as boost.",
                tuningNote: "Tune for fast, stable response: too much gain oscillates, too little is laggy. Usually adjusted only after the feed-forward tables are right.")),
        Entry(keywords: ["torque", "moment", "drehmoment"],
              insight: CalibrationInsight(
                summary: "Torque request, modelling or limiting in the ECU's torque-based control structure.",
                tuningNote: "The S58 is torque-managed: even with more boost, torque limiters and the driver-demand map will cap output unless they are raised together.")),
        Entry(keywords: ["load", "last", "füllung", "fuellung", "charge"],
              insight: CalibrationInsight(
                summary: "Engine load / air-charge target or limit (relative cylinder filling).",
                tuningNote: "Load ceilings are a common hidden limiter — raising boost without raising the load limits leaves power on the table or trips a fault.")),
        Entry(keywords: ["rail", "raildruck", "injection", "einspritz", "injector", "di usage"],
              insight: CalibrationInsight(
                summary: "Direct-injection fuel rail pressure or injection timing/quantity parameters.",
                tuningNote: "Rail pressure must keep up with fuel demand at high load; on E-blends the S58 needs more fuel, making these and PI (port injection) tables important.")),
        Entry(keywords: ["flex", "ethanol", "pi ", "port injection"],
              insight: CalibrationInsight(
                summary: "Flex-fuel / ethanol blending and port-injection control.",
                tuningNote: "Higher ethanol content allows more timing and boost; these tables scale fueling and limits with measured ethanol percentage.")),
        Entry(keywords: ["maf", "mass flow", "massflow", "luftmasse"],
              insight: CalibrationInsight(
                summary: "Mass-airflow modelling and sensor calibration.",
                tuningNote: "Accurate airflow is the basis of fueling and load; errors here cascade into lambda and torque errors.")),
        Entry(keywords: ["vanos", "camshaft", "nockenwelle", "cam "],
              insight: CalibrationInsight(
                summary: "VANOS variable camshaft timing targets (intake/exhaust).",
                tuningNote: "Cam phasing shapes the torque curve and scavenging. Small changes interact strongly with boost and emissions on the S58.")),
        Entry(keywords: ["egt", "exhaust", "abgas", "temperature", "temperatur", "öl", "oel", "oil", "coolant", "wasser", "iat", "ansaug"],
              insight: CalibrationInsight(
                summary: "A temperature value, limit, or temperature-based compensation/protection.",
                tuningNote: "Drives protection and trims. Component-protection enrichment and timing pull are temperature-gated, so these shape both safety and hot-weather performance.")),
        Entry(keywords: ["rev limit", "drehzahlbegrenzung", "rpm limit", "maximaldrehzahl", "limiter"],
              insight: CalibrationInsight(
                summary: "Engine speed limiter and related fuel/spark cut behaviour.",
                tuningNote: "Raise only within the rotating assembly's safe range; also check valvetrain limits before extending the S58's rev ceiling.")),
        Entry(keywords: ["throttle", "drossel", "pedal", "driver demand", "fahrer"],
              insight: CalibrationInsight(
                summary: "Throttle / pedal mapping and driver torque demand.",
                tuningNote: "Shapes throttle response and how much torque a given pedal position requests — felt immediately by the driver.")),
        Entry(keywords: ["idle", "leerlauf"],
              insight: CalibrationInsight(
                summary: "Idle speed control and related fueling/timing.",
                tuningNote: "Mostly drivability; relevant after cam or injector changes that upset idle quality.")),
        Entry(keywords: ["burble", "pop", "antilag", "racestart", "launch", "crackle"],
              insight: CalibrationInsight(
                summary: "MHD+ feature map (e.g. burble/crackle, antilag, launch/race start).",
                tuningNote: "Aftermarket feature layer rather than an OEM table — tune for effect and drivability; aggressive settings add heat and wear.")),
    ]

    private static func categoryFallback(_ category: CalibrationCategory) -> CalibrationInsight {
        switch category {
        case .fuel:
            return CalibrationInsight(summary: "A fueling-related table.",
                                      tuningNote: "Affects air/fuel ratio and fuel delivery on the S58.")
        case .ignition:
            return CalibrationInsight(summary: "An ignition-related table.",
                                      tuningNote: "Affects spark timing — power versus knock margin on the S58.")
        case .boost:
            return CalibrationInsight(summary: "A boost/airflow-related table.",
                                      tuningNote: "Affects how much air the S58's turbos deliver and how load is limited.")
        case .torque:
            return CalibrationInsight(summary: "A torque-management table.",
                                      tuningNote: "Part of the S58's torque model/limiters that can cap output.")
        case .safety:
            return CalibrationInsight(summary: "A protection/limit table.",
                                      tuningNote: "Guards the engine; understand it before changing as it exists to prevent damage.")
        case .other:
            return CalibrationInsight(summary: "A calibration table for this ROM.",
                                      tuningNote: "Tap “Look up online” for a detailed explanation of this specific parameter.")
        }
    }
}
