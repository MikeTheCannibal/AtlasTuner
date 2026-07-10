import Foundation
import Network

/// A ``ByteTransport`` over TCP using Network.framework — the wired path for DoIP: the OBD port's
/// automotive Ethernet is bridged to the Mac/iPad via an RJ45 (100BASE-T1 ↔ 100BASE-TX) adapter,
/// the vehicle appears at a link-local address, and diagnostics run on TCP port 13400.
///
/// Vehicle discovery (the UDP vehicle-identification broadcast) is out of scope here; construct
/// this with the DoIP entity's address once known (statically configured, or from a prior
/// announcement). Receiving hands raw chunks up to `DoIPClient`, which reassembles frames.
public final class TCPByteTransport: ByteTransport, @unchecked Sendable {
    private let endpoint: NWEndpoint
    private let queue = DispatchQueue(label: "com.atlastune.doip.tcp")
    private var connection: NWConnection?

    public init(host: String, port: UInt16 = doIPPort) {
        self.endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host),
                                            port: NWEndpoint.Port(rawValue: port) ?? 13400)
    }

    public func open() async throws {
        let parameters = NWParameters.tcp
        // Diagnostics are latency-sensitive and small; disable Nagle so requests go out promptly.
        if let tcp = parameters.defaultProtocolStack.transportProtocol as? NWProtocolTCP.Options {
            tcp.noDelay = true
        }
        let connection = NWConnection(to: endpoint, using: parameters)
        self.connection = connection

        // `stateUpdateHandler` may fire repeatedly; `once` makes the continuation resume exactly
        // once (and is concurrency-safe, unlike a captured `var`).
        let once = ResumeOnce()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    once.fire { continuation.resume() }
                case .failed(let error), .waiting(let error):
                    once.fire { continuation.resume(throwing: TransportError.failed("\(error)")) }
                case .cancelled:
                    once.fire { continuation.resume(throwing: TransportError.closed) }
                default:
                    break
                }
            }
            connection.start(queue: queue)
        }
    }

    public func send(_ bytes: [UInt8]) async throws {
        guard let connection else { throw TransportError.notConnected }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: Data(bytes), completion: .contentProcessed { error in
                if let error { continuation.resume(throwing: TransportError.failed("\(error)")) }
                else { continuation.resume() }
            })
        }
    }

    public func receive() async throws -> [UInt8] {
        guard let connection else { throw TransportError.notConnected }
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[UInt8], Error>) in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
                if let error { continuation.resume(throwing: TransportError.failed("\(error)")); return }
                if let data, !data.isEmpty { continuation.resume(returning: Array(data)); return }
                if isComplete { continuation.resume(throwing: TransportError.closed); return }
                continuation.resume(returning: [])
            }
        }
    }

    public func close() {
        connection?.cancel()
        connection = nil
    }
}

/// Runs its closure the first time `fire` is called and never again — a concurrency-safe
/// one-shot guard for continuations resumed from a callback that may fire more than once.
private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func fire(_ body: () -> Void) {
        lock.lock()
        if done { lock.unlock(); return }
        done = true
        lock.unlock()
        body()
    }
}
