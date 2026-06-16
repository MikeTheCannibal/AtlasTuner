import Foundation

/// Diagnostics over IP (DoIP, ISO 13400) message framing — the transport BMW F/G-series ECUs use
/// over an ENET (Ethernet) cable. This type only builds and parses the byte frames; the actual
/// TCP socket lives in the app layer (`ENETDatalogSource`), keeping this engine module
/// Foundation-only and unit-testable.
public enum DoIP {
    public static let defaultPort: UInt16 = 13400
    public static let protocolVersion: UInt8 = 0x02   // ISO 13400-2:2012

    public enum PayloadType: UInt16, Sendable {
        case routingActivationRequest  = 0x0005
        case routingActivationResponse = 0x0006
        case aliveCheckRequest         = 0x0007
        case aliveCheckResponse        = 0x0008
        case diagnosticMessage         = 0x8001
        case diagnosticAck             = 0x8002   // positive ACK
        case diagnosticNack            = 0x8003   // negative ACK
    }

    /// A parsed DoIP message: payload type plus its raw payload bytes.
    public struct Message: Equatable, Sendable {
        public let type: UInt16
        public let payload: [UInt8]
        public init(type: UInt16, payload: [UInt8]) {
            self.type = type
            self.payload = payload
        }
    }

    // MARK: Builders

    public static func frame(type: UInt16, payload: [UInt8]) -> [UInt8] {
        var bytes: [UInt8] = [protocolVersion, protocolVersion ^ 0xFF]
        bytes += beUInt16(type)
        bytes += beUInt32(UInt32(payload.count))
        bytes += payload
        return bytes
    }

    /// Routing activation request (must succeed before diagnostic messages are accepted).
    public static func routingActivation(sourceAddress: UInt16, activationType: UInt8 = 0x00) -> [UInt8] {
        var payload = beUInt16(sourceAddress)
        payload.append(activationType)
        payload += [0x00, 0x00, 0x00, 0x00]   // ISO reserved
        return frame(type: PayloadType.routingActivationRequest.rawValue, payload: payload)
    }

    /// Wrap a UDS service request in a DoIP diagnostic message.
    public static func diagnosticMessage(source: UInt16, target: UInt16, uds: [UInt8]) -> [UInt8] {
        var payload = beUInt16(source) + beUInt16(target)
        payload += uds
        return frame(type: PayloadType.diagnosticMessage.rawValue, payload: payload)
    }

    // MARK: Parser

    /// Parse the first complete DoIP message at the front of `data`. Returns the message and how
    /// many bytes it consumed, or `nil` if a full frame is not yet present (need more bytes).
    public static func parse(_ data: [UInt8]) -> (message: Message, consumed: Int)? {
        guard data.count >= 8 else { return nil }
        let type = beUInt16(data[2], data[3])
        let length = beUInt32(data[4], data[5], data[6], data[7])
        let total = 8 + Int(length)
        guard data.count >= total else { return nil }
        return (Message(type: type, payload: Array(data[8..<total])), total)
    }

    /// Extract the UDS bytes from a diagnostic-message payload (source(2) + target(2) + UDS).
    public static func udsBytes(fromDiagnosticPayload payload: [UInt8]) -> [UInt8]? {
        guard payload.count > 4 else { return nil }
        return Array(payload[4...])
    }

    public static func isRoutingActivationSuccess(_ message: Message) -> Bool {
        guard message.type == PayloadType.routingActivationResponse.rawValue,
              message.payload.count >= 5 else { return false }
        // Byte index 4 = activation response code; 0x10 = "routing successfully activated".
        return message.payload[4] == 0x10
    }

    // MARK: Big-endian helpers

    static func beUInt16(_ v: UInt16) -> [UInt8] { [UInt8(v >> 8), UInt8(v & 0xFF)] }
    static func beUInt32(_ v: UInt32) -> [UInt8] {
        [UInt8((v >> 24) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)]
    }
    static func beUInt16(_ hi: UInt8, _ lo: UInt8) -> UInt16 { UInt16(hi) << 8 | UInt16(lo) }
    static func beUInt32(_ a: UInt8, _ b: UInt8, _ c: UInt8, _ d: UInt8) -> UInt32 {
        UInt32(a) << 24 | UInt32(b) << 16 | UInt32(c) << 8 | UInt32(d)
    }
}
