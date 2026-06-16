import Foundation

/// A single measured signal in a datalog. The Phase 1 S58 channel set is provided as
/// constants, but channels are data so logging sources can declare their own.
public struct LogChannel: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var unit: String

    public init(id: String, name: String, unit: String) {
        self.id = id
        self.name = name
        self.unit = unit
    }
}

public extension LogChannel {
    static let rpm = LogChannel(id: "rpm", name: "Engine Speed", unit: "rpm")
    static let boost = LogChannel(id: "boost", name: "Boost Pressure", unit: "psi")
    static let load = LogChannel(id: "load", name: "Engine Load", unit: "%")
    static let lambda = LogChannel(id: "lambda", name: "Lambda", unit: "λ")
    static let ignitionTiming = LogChannel(id: "ign", name: "Ignition Timing", unit: "°")
    static let knock = LogChannel(id: "knock", name: "Knock Activity", unit: "°")
    static let wgdc = LogChannel(id: "wgdc", name: "Wastegate Duty", unit: "%")
    static let fuelTrim = LogChannel(id: "ftrim", name: "Fuel Trim", unit: "%")
    static let iat = LogChannel(id: "iat", name: "Intake Air Temp", unit: "°C")
    static let coolant = LogChannel(id: "ect", name: "Coolant Temp", unit: "°C")
    static let torque = LogChannel(id: "torque", name: "Torque", unit: "Nm")

    /// Canonical S58 channel set expected by the logging engine.
    static let s58Standard: [LogChannel] = [
        .rpm, .boost, .load, .lambda, .ignitionTiming, .knock,
        .wgdc, .fuelTrim, .iat, .coolant, .torque,
    ]
}
