import Foundation
import Network
import AtlasTuneCore

/// A minimal DoIP (ISO 13400) client over TCP: connect, routing-activate, then issue UDS requests
/// and read their responses. Shared by live logging (`ENETDatalogSource`) and ROM reading
/// (`VehicleROMReader`). Drive a single instance from one task.
final class DoIPClient: @unchecked Sendable {
    enum ClientError: Error { case routingFailed, connectionClosed, cancelled, notConnected }

    let testerAddress: UInt16
    let ecuAddress: UInt16

    private let host: NWEndpoint.Host
    private let port: NWEndpoint.Port
    private var connection: NWConnection?
    private var buffer: [UInt8] = []

    init(host: String, port: UInt16 = DoIP.defaultPort, testerAddress: UInt16, ecuAddress: UInt16) {
        self.host = NWEndpoint.Host(host)
        self.port = NWEndpoint.Port(rawValue: port) ?? 13400
        self.testerAddress = testerAddress
        self.ecuAddress = ecuAddress
    }

    /// Open the TCP connection and perform DoIP routing activation.
    func connect() async throws {
        let connection = NWConnection(host: host, port: port, using: .tcp)
        self.connection = connection
        try await waitReady(connection)
        try await sendRaw(DoIP.routingActivation(sourceAddress: testerAddress), on: connection)
        let response = try await receiveDoIP(on: connection)
        guard DoIP.isRoutingActivationSuccess(response) else { throw ClientError.routingFailed }
    }

    /// Issue a UDS request and return its UDS response bytes (negatives included; `0x78` pending is
    /// handled internally).
    @discardableResult
    func request(_ uds: [UInt8]) async throws -> [UInt8] {
        guard let connection else { throw ClientError.notConnected }
        try await sendRaw(DoIP.diagnosticMessage(source: testerAddress, target: ecuAddress, uds: uds), on: connection)
        while true {
            let message = try await receiveDoIP(on: connection)
            guard message.type == DoIP.PayloadType.diagnosticMessage.rawValue,
                  let response = DoIP.udsBytes(fromDiagnosticPayload: message.payload) else {
                continue // ACK / alive-check
            }
            if let parsed = UDS.parse(response), UDS.isResponsePending(parsed) { continue }
            return response
        }
    }

    func cancel() {
        connection?.cancel()
        connection = nil
    }

    // MARK: NWConnection bridges

    private func waitReady(_ connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            connection.stateUpdateHandler = { [weak connection] state in
                switch state {
                case .ready:
                    connection?.stateUpdateHandler = nil; cont.resume()
                case .failed(let error):
                    connection?.stateUpdateHandler = nil; cont.resume(throwing: error)
                case .cancelled:
                    connection?.stateUpdateHandler = nil; cont.resume(throwing: ClientError.cancelled)
                default:
                    break
                }
            }
            connection.start(queue: .global(qos: .userInitiated))
        }
    }

    private func sendRaw(_ bytes: [UInt8], on connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            connection.send(content: Data(bytes), completion: .contentProcessed { error in
                if let error { cont.resume(throwing: error) } else { cont.resume() }
            })
        }
    }

    private func receiveDoIP(on connection: NWConnection) async throws -> DoIP.Message {
        while true {
            if let (message, consumed) = DoIP.parse(buffer) {
                buffer.removeFirst(consumed)
                return message
            }
            let chunk = try await receiveChunk(on: connection)
            buffer.append(contentsOf: chunk)
        }
    }

    private func receiveChunk(on connection: NWConnection) async throws -> [UInt8] {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<[UInt8], Error>) in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, isComplete, error in
                if let error { cont.resume(throwing: error); return }
                if let data, !data.isEmpty { cont.resume(returning: [UInt8](data)); return }
                if isComplete { cont.resume(throwing: ClientError.connectionClosed); return }
                cont.resume(returning: [])
            }
        }
    }
}
