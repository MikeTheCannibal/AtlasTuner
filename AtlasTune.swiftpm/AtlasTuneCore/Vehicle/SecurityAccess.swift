import Foundation

/// Computes a UDS security-access key from a seed, to unlock protected operations such as reading
/// flash. The MG1/S58 seed→key algorithm is proprietary and is NOT included with Atlas Tune; supply
/// your own implementation (one you are authorised to use for your vehicle) by conforming to this
/// protocol. Without it, the ECU will deny protected reads.
public protocol SecurityAccessProvider: Sendable {
    /// The security level to request (odd sub-function, e.g. 0x01 / 0x11).
    var level: UInt8 { get }
    /// Derive the key for the given seed.
    func key(forSeed seed: [UInt8]) -> [UInt8]
}

/// Default provider: performs no unlock. Reads of unprotected regions (and many identification
/// services) still work; protected flash reads will be refused by the ECU.
public struct NoSecurityAccess: SecurityAccessProvider {
    public let level: UInt8 = 0x01
    public init() {}
    public func key(forSeed seed: [UInt8]) -> [UInt8] { [] }
}
