import Foundation

/// ISO 13400-2 (Diagnostics over IP) message framing. A DoIP message is an 8-byte generic header
/// — protocol version, its bitwise inverse, a 16-bit payload type and a 32-bit payload length —
/// followed by the payload. All multi-byte fields are big-endian. This type encodes/decodes the
/// header and the handful of payloads Atlas Tune needs to stand up a live diagnostic session over
/// an Ethernet/RJ45 link to the OBD port; UDS service bytes ride inside the diagnostic payload.
public struct DoIPMessage: Sendable, Equatable {
    /// ISO 13400-2:2012 uses 0x02; :2019 uses 0x03. BMW G-series accept 0x02.
    public static let protocolVersion: UInt8 = 0x02

    public var payloadType: PayloadType
    public var payload: [UInt8]

    public init(payloadType: PayloadType, payload: [UInt8]) {
        self.payloadType = payloadType
        self.payload = payload
    }

    public enum PayloadType: UInt16, Sendable {
        case genericNegativeAck = 0x0000
        case vehicleIdentificationRequest = 0x0001
        case vehicleAnnouncement = 0x0004          // also the identification response
        case routingActivationRequest = 0x0005
        case routingActivationResponse = 0x0006
        case aliveCheckRequest = 0x0007
        case aliveCheckResponse = 0x0008
        case diagnosticMessage = 0x8001
        case diagnosticMessagePositiveAck = 0x8002
        case diagnosticMessageNegativeAck = 0x8003
    }

    public enum DecodeError: Error, Equatable {
        case tooShort                       // fewer than 8 header bytes
        case protocolMismatch               // version / inverse-version disagree
        case unknownPayloadType(UInt16)
        case truncatedPayload(expected: Int, got: Int)
    }

    // MARK: Encoding

    public func encoded() -> [UInt8] {
        var out: [UInt8] = [
            Self.protocolVersion,
            ~Self.protocolVersion,
        ]
        out.appendBigEndian(payloadType.rawValue)
        out.appendBigEndian(UInt32(payload.count))
        out += payload
        return out
    }

    /// Decode exactly one message from the front of `bytes`, returning it plus the number of bytes
    /// consumed (header + payload). Use `framedLength` first when reading from a stream.
    public static func decode(_ bytes: [UInt8]) throws -> (message: DoIPMessage, consumed: Int) {
        guard bytes.count >= 8 else { throw DecodeError.tooShort }
        guard bytes[0] == protocolVersion, bytes[1] == UInt8(~protocolVersion) else {
            throw DecodeError.protocolMismatch
        }
        let rawType = UInt16(bytes[2]) << 8 | UInt16(bytes[3])
        guard let type = PayloadType(rawValue: rawType) else {
            throw DecodeError.unknownPayloadType(rawType)
        }
        let length = Int(UInt32(bytes[4]) << 24 | UInt32(bytes[5]) << 16 | UInt32(bytes[6]) << 8 | UInt32(bytes[7]))
        guard bytes.count >= 8 + length else {
            throw DecodeError.truncatedPayload(expected: 8 + length, got: bytes.count)
        }
        let payload = Array(bytes[8..<(8 + length)])
        return (DoIPMessage(payloadType: type, payload: payload), 8 + length)
    }

    /// Total framed length of the message at the front of `bytes` (header + declared payload), or
    /// `nil` if fewer than 8 header bytes are available yet. Lets a stream reader know when a full
    /// message has arrived without copying.
    public static func framedLength(_ bytes: [UInt8]) -> Int? {
        guard bytes.count >= 8 else { return nil }
        let length = Int(UInt32(bytes[4]) << 24 | UInt32(bytes[5]) << 16 | UInt32(bytes[6]) << 8 | UInt32(bytes[7]))
        return 8 + length
    }

    // MARK: Payload builders / parsers

    /// Routing activation request (ISO 13400 §7.5): source address + activation type + reserved.
    public static func routingActivation(sourceAddress: UInt16, activationType: UInt8 = 0x00) -> DoIPMessage {
        var payload: [UInt8] = []
        payload.appendBigEndian(sourceAddress)
        payload.append(activationType)
        payload += [0, 0, 0, 0]                 // ISO reserved
        return DoIPMessage(payloadType: .routingActivationRequest, payload: payload)
    }

    /// The routing-activation response code (byte 4 of the payload); 0x10 = success.
    public struct RoutingActivationResult: Sendable, Equatable {
        public let testerAddress: UInt16
        public let entityAddress: UInt16
        public let responseCode: UInt8
        public var isSuccess: Bool { responseCode == 0x10 }
    }

    public func routingActivationResult() -> RoutingActivationResult? {
        guard payloadType == .routingActivationResponse, payload.count >= 5 else { return nil }
        return RoutingActivationResult(
            testerAddress: UInt16(payload[0]) << 8 | UInt16(payload[1]),
            entityAddress: UInt16(payload[2]) << 8 | UInt16(payload[3]),
            responseCode: payload[4]
        )
    }

    /// Diagnostic message (ISO 13400 §7.6): source + target logical addresses, then UDS bytes.
    public static func diagnostic(source: UInt16, target: UInt16, uds: [UInt8]) -> DoIPMessage {
        var payload: [UInt8] = []
        payload.appendBigEndian(source)
        payload.appendBigEndian(target)
        payload += uds
        return DoIPMessage(payloadType: .diagnosticMessage, payload: payload)
    }

    /// The UDS bytes carried by a diagnostic message (skipping the 4 source/target address bytes),
    /// or `nil` if this isn't a diagnostic message.
    public func diagnosticUDS() -> [UInt8]? {
        guard payloadType == .diagnosticMessage, payload.count >= 4 else { return nil }
        return Array(payload[4...])
    }
}

extension Array where Element == UInt8 {
    mutating func appendBigEndian(_ value: UInt16) {
        append(UInt8(value >> 8)); append(UInt8(value & 0xFF))
    }
    mutating func appendBigEndian(_ value: UInt32) {
        append(UInt8(value >> 24 & 0xFF)); append(UInt8(value >> 16 & 0xFF))
        append(UInt8(value >> 8 & 0xFF)); append(UInt8(value & 0xFF))
    }
}
