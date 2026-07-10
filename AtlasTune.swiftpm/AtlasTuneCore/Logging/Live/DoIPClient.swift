import Foundation

/// Drives a DoIP diagnostic session over any ``ByteTransport``: performs routing activation, then
/// polls `ReadDataByIdentifier` for each configured DID and decodes the responses into channel
/// values. The transport (wired Ethernet, BLE, mock) and the DID set are both injected, so this
/// orchestration is pure protocol logic and testable against an in-memory ECU.
public actor DoIPClient {
    public struct Configuration: Sendable {
        /// Tester (client) logical address. 0x0E00 is the conventional external-tester address.
        public var sourceAddress: UInt16
        /// ECU (DoIP entity) logical address to target in diagnostic messages.
        public var targetAddress: UInt16
        /// How long to wait for each response before giving up on it.
        public var responseTimeout: Duration
        /// Max retries when the ECU answers 0x78 (response pending).
        public var responsePendingRetries: Int

        public init(sourceAddress: UInt16 = 0x0E00, targetAddress: UInt16 = 0x1001,
                    responseTimeout: Duration = .seconds(1), responsePendingRetries: Int = 3) {
            self.sourceAddress = sourceAddress
            self.targetAddress = targetAddress
            self.responseTimeout = responseTimeout
            self.responsePendingRetries = responsePendingRetries
        }
    }

    public enum ClientError: Error, Equatable {
        case routingActivationFailed(code: UInt8)
        case unexpectedMessage
        case negativeResponse(UDSService.NegativeResponseCode)
        case decodeFailed
    }

    private let transport: ByteTransport
    private let configuration: Configuration
    private let decoder = LiveChannelDecoder()
    private var inbox: [UInt8] = []

    public init(transport: ByteTransport, configuration: Configuration = Configuration()) {
        self.transport = transport
        self.configuration = configuration
    }

    // MARK: Session lifecycle

    /// Open the transport and perform routing activation. Throws on activation failure.
    public func activate() async throws {
        try await transport.open()
        try await sendDoIP(.routingActivation(sourceAddress: configuration.sourceAddress))
        let response = try await nextDoIP(matching: [.routingActivationResponse])
        guard let result = response.routingActivationResult() else { throw ClientError.unexpectedMessage }
        guard result.isSuccess else { throw ClientError.routingActivationFailed(code: result.responseCode) }
    }

    public func close() {
        transport.close()
    }

    // MARK: Reads

    /// Read one DID and return its raw response data (after the 0x62+DID echo). Handles a 0x78
    /// response-pending by waiting for the follow-up, up to the configured retry count.
    public func readData(_ did: UInt16) async throws -> [UInt8] {
        try await sendDoIP(.diagnostic(source: configuration.sourceAddress,
                                       target: configuration.targetAddress,
                                       uds: UDSService.readDataByIdentifier(did)))
        var pendingRetries = configuration.responsePendingRetries
        while true {
            let message = try await nextDoIP(matching: [.diagnosticMessage,
                                                        .diagnosticMessagePositiveAck,
                                                        .diagnosticMessageNegativeAck])
            // The ECU acks the request first; the data arrives in a following diagnostic message.
            guard message.payloadType == .diagnosticMessage, let uds = message.diagnosticUDS() else {
                continue
            }
            switch try UDSService.parse(uds) {
            case .positive(let responseDID, let data):
                guard responseDID == did else { continue }
                return data
            case .negative(_, let code):
                if code.isResponsePending, pendingRetries > 0 { pendingRetries -= 1; continue }
                throw ClientError.negativeResponse(code)
            }
        }
    }

    /// Poll every identifier once and assemble a `LogSample` at time `time`. DIDs that fail to
    /// read or decode are simply absent from the sample (graceful partial reads).
    public func sample(_ identifiers: [UDSDataIdentifier], at time: TimeInterval) async -> LogSample {
        var values: [String: Double] = [:]
        for identifier in identifiers {
            guard let data = try? await readData(identifier.did),
                  let value = decoder.value(identifier, from: data) else { continue }
            values[identifier.channel.id] = value
        }
        return LogSample(time: time, values: values)
    }

    // MARK: Framed transport helpers

    private func sendDoIP(_ message: DoIPMessage) async throws {
        try await transport.send(message.encoded())
    }

    /// Read and reassemble the next complete DoIP message whose type is in `types`, buffering
    /// partial frames and skipping unrelated ones (e.g. alive-check requests).
    private func nextDoIP(matching types: [DoIPMessage.PayloadType]) async throws -> DoIPMessage {
        let deadline = ContinuousClock.now.advanced(by: configuration.responseTimeout)
        while true {
            if let framed = DoIPMessage.framedLength(inbox), inbox.count >= framed {
                let (message, consumed) = try DoIPMessage.decode(inbox)
                inbox.removeFirst(consumed)
                if types.contains(message.payloadType) { return message }
                continue    // not what we're waiting for; keep draining the buffer
            }
            if ContinuousClock.now >= deadline { throw TransportError.timeout }
            let chunk = try await transport.receive()
            inbox += chunk
        }
    }
}
