import Foundation
import Network
import AtlasTuneCore

/// Live datalog source over a BMW ENET (Ethernet) cable using DoIP (ISO 13400) + UDS (ISO 14229).
///
/// It connects to the vehicle's DoIP gateway over TCP, performs routing activation, optionally
/// enters an extended diagnostic session, then polls the configured data identifiers on a timer,
/// decoding each response into a `LogSample`. It conforms to `DatalogSource`, so it flows into the
/// same pipeline as the demo and replay sources (live tiles, heat map, raw table, CSV export).
///
/// Protocol framing/transport here is real. The S58 DID map it reads (`ENETChannelMap.s58Placeholder`)
/// is a placeholder pending verified identifiers, and live connections require the device to be on
/// the vehicle's network (local-network permission). See Docs for details.
final class ENETDatalogSource: DatalogSource, @unchecked Sendable {
    enum ENETError: Error { case routingFailed, connectionClosed, cancelled }

    let map: ENETChannelMap
    var channels: [LogChannel] { map.channels }

    private let host: NWEndpoint.Host
    private let port: NWEndpoint.Port
    private let rate: Double
    private let useExtendedSession: Bool

    private var connection: NWConnection?
    private var task: Task<Void, Never>?
    private var buffer: [UInt8] = []

    init(host: String,
         port: UInt16 = DoIP.defaultPort,
         map: ENETChannelMap = .s58Placeholder,
         rate: Double = 20,
         extendedSession: Bool = true) {
        self.host = NWEndpoint.Host(host)
        self.port = NWEndpoint.Port(rawValue: port) ?? 13400
        self.map = map
        self.rate = rate
        self.useExtendedSession = extendedSession
    }

    func start() -> AsyncStream<LogSample> {
        AsyncStream { continuation in
            let task = Task { [weak self] in
                guard let self else { continuation.finish(); return }
                do { try await self.run { continuation.yield($0) } }
                catch { /* connection ended or failed */ }
                continuation.finish()
            }
            self.task = task
            continuation.onTermination = { [weak self] _ in self?.stop() }
        }
    }

    func stop() {
        task?.cancel()
        connection?.cancel()
        connection = nil
    }

    // MARK: Session

    private func run(yield: @escaping (LogSample) -> Void) async throws {
        let connection = NWConnection(host: host, port: port, using: .tcp)
        self.connection = connection
        try await connect(connection)

        try await send(DoIP.routingActivation(sourceAddress: map.testerAddress), on: connection)
        let activation = try await receiveDoIP(on: connection)
        guard DoIP.isRoutingActivationSuccess(activation) else { throw ENETError.routingFailed }

        if useExtendedSession {
            _ = try? await diagnosticRequest(UDS.sessionControlRequest(UDS.extendedSession), on: connection)
        }

        let startTime = Date()
        let interval = rate > 0 ? UInt64(1_000_000_000 / rate) : 0
        let dids = map.dids

        while !Task.isCancelled {
            var responses: [UInt16: [UInt8]] = [:]
            for did in dids {
                if Task.isCancelled { break }
                guard let uds = try? await diagnosticRequest(UDS.readDataByIdentifierRequest(did), on: connection),
                      let parsed = UDS.readDataResponse(uds) else { continue }
                responses[parsed.did] = parsed.data
            }
            let time = Date().timeIntervalSince(startTime)
            yield(ENETDecoder(map: map).sample(time: time, responses: responses))
            if interval > 0 { try? await Task.sleep(nanoseconds: interval) }
        }
    }

    /// Send a UDS request and wait for its diagnostic-message response, skipping ACKs and
    /// honouring 0x78 "response pending".
    private func diagnosticRequest(_ uds: [UInt8], on connection: NWConnection) async throws -> [UInt8] {
        let frame = DoIP.diagnosticMessage(source: map.testerAddress, target: map.ecuAddress, uds: uds)
        try await send(frame, on: connection)
        while true {
            let message = try await receiveDoIP(on: connection)
            guard message.type == DoIP.PayloadType.diagnosticMessage.rawValue,
                  let response = DoIP.udsBytes(fromDiagnosticPayload: message.payload) else {
                continue // ACK, alive-check, etc.
            }
            if let parsed = UDS.parse(response), UDS.isResponsePending(parsed) { continue }
            return response
        }
    }

    // MARK: NWConnection bridges

    private func connect(_ connection: NWConnection) async throws {
        // States are delivered serially; clearing the handler on the first terminal state prevents
        // any second resume of the continuation.
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            connection.stateUpdateHandler = { [weak connection] state in
                switch state {
                case .ready:
                    connection?.stateUpdateHandler = nil
                    cont.resume()
                case .failed(let error):
                    connection?.stateUpdateHandler = nil
                    cont.resume(throwing: error)
                case .cancelled:
                    connection?.stateUpdateHandler = nil
                    cont.resume(throwing: ENETError.cancelled)
                default:
                    break
                }
            }
            connection.start(queue: .global(qos: .userInitiated))
        }
    }

    private func send(_ bytes: [UInt8], on connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            connection.send(content: Data(bytes), completion: .contentProcessed { error in
                if let error { cont.resume(throwing: error) } else { cont.resume() }
            })
        }
    }

    /// Receive bytes until a full DoIP frame can be parsed out of the rolling buffer.
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
                if isComplete { cont.resume(throwing: ENETError.connectionClosed); return }
                cont.resume(returning: [])
            }
        }
    }
}
