import Foundation

/// Unified Diagnostic Services (UDS, ISO 14229) request/response helpers, used for live logging by
/// repeatedly reading data identifiers. Pure byte logic — testable without a vehicle.
public enum UDS {
    // Service IDs
    public static let readDataByIdentifier: UInt8 = 0x22
    public static let diagnosticSessionControl: UInt8 = 0x10
    public static let negativeResponse: UInt8 = 0x7F

    /// Sessions
    public static let defaultSession: UInt8 = 0x01
    public static let extendedSession: UInt8 = 0x03

    public static func readDataByIdentifierRequest(_ did: UInt16) -> [UInt8] {
        [readDataByIdentifier, UInt8(did >> 8), UInt8(did & 0xFF)]
    }

    public static func sessionControlRequest(_ session: UInt8) -> [UInt8] {
        [diagnosticSessionControl, session]
    }

    public enum Response: Equatable, Sendable {
        case positive(service: UInt8, data: [UInt8])
        case negative(service: UInt8, code: UInt8)
    }

    public static func parse(_ uds: [UInt8]) -> Response? {
        guard let first = uds.first else { return nil }
        if first == negativeResponse, uds.count >= 3 {
            return .negative(service: uds[1], code: uds[2])
        }
        return .positive(service: first, data: Array(uds.dropFirst()))
    }

    /// For a positive ReadDataByIdentifier response (0x62 DID_hi DID_lo data...), return the DID
    /// and its data bytes.
    public static func readDataResponse(_ uds: [UInt8]) -> (did: UInt16, data: [UInt8])? {
        guard uds.count >= 3, uds[0] == readDataByIdentifier + 0x40 else { return nil }
        let did = UInt16(uds[1]) << 8 | UInt16(uds[2])
        return (did, Array(uds.dropFirst(3)))
    }

    /// 0x78 (responsePending) is sent by the ECU to ask the tester to keep waiting.
    public static func isResponsePending(_ response: Response) -> Bool {
        if case let .negative(_, code) = response { return code == 0x78 }
        return false
    }
}
