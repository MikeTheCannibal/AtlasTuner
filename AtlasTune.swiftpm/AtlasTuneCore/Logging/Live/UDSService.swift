import Foundation

/// The slice of UDS (ISO 14229) needed for live datalogging: building `ReadDataByIdentifier`
/// requests and parsing their responses, including negative-response decoding.
public enum UDSService {
    public static let readDataByIdentifier: UInt8 = 0x22
    public static let positiveResponseOffset: UInt8 = 0x40   // response SID = request SID + 0x40
    public static let negativeResponse: UInt8 = 0x7F

    /// Build a `ReadDataByIdentifier` request for one DID: `0x22 <DID hi> <DID lo>`.
    public static func readDataByIdentifier(_ did: UInt16) -> [UInt8] {
        [readDataByIdentifier, UInt8(did >> 8), UInt8(did & 0xFF)]
    }

    public enum Response: Sendable, Equatable {
        /// Positive `0x62` response: the echoed DID and its data bytes.
        case positive(did: UInt16, data: [UInt8])
        /// Negative `0x7F` response: the rejected service id and the NRC.
        case negative(service: UInt8, code: NegativeResponseCode)
    }

    public enum ParseError: Error, Equatable {
        case empty
        case unexpectedService(UInt8)
        case truncated
    }

    /// Parse a UDS response PDU (the bytes carried inside a DoIP diagnostic message).
    public static func parse(_ bytes: [UInt8]) throws -> Response {
        guard let first = bytes.first else { throw ParseError.empty }
        if first == negativeResponse {
            guard bytes.count >= 3 else { throw ParseError.truncated }
            return .negative(service: bytes[1], code: NegativeResponseCode(rawValue: bytes[2]) ?? .other(bytes[2]))
        }
        guard first == readDataByIdentifier + positiveResponseOffset else {
            throw ParseError.unexpectedService(first)
        }
        guard bytes.count >= 3 else { throw ParseError.truncated }
        let did = UInt16(bytes[1]) << 8 | UInt16(bytes[2])
        return .positive(did: did, data: Array(bytes[3...]))
    }

    /// A subset of ISO 14229 negative-response codes worth surfacing to the user.
    public enum NegativeResponseCode: Sendable, Equatable {
        case generalReject                 // 0x10
        case serviceNotSupported           // 0x11
        case subFunctionNotSupported       // 0x12
        case busyRepeatRequest             // 0x21
        case conditionsNotCorrect          // 0x22
        case requestOutOfRange             // 0x31
        case securityAccessDenied          // 0x33
        case responsePending               // 0x78 — ECU needs more time; retry
        case other(UInt8)

        public init?(rawValue: UInt8) {
            switch rawValue {
            case 0x10: self = .generalReject
            case 0x11: self = .serviceNotSupported
            case 0x12: self = .subFunctionNotSupported
            case 0x21: self = .busyRepeatRequest
            case 0x22: self = .conditionsNotCorrect
            case 0x31: self = .requestOutOfRange
            case 0x33: self = .securityAccessDenied
            case 0x78: self = .responsePending
            default: self = .other(rawValue)
            }
        }

        /// Response-pending (0x78) is transient — the client should wait for the follow-up.
        public var isResponsePending: Bool { self == .responsePending }
    }
}
