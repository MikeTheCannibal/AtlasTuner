import Foundation

/// A bidirectional byte pipe the DoIP client talks over. Abstracting the socket lets the exact
/// same protocol logic run over a wired Ethernet/RJ45 link (`TCPByteTransport`, ISO 13400 default
/// TCP port 13400), a future BLE OBD adapter, or an in-memory mock for tests — none of which the
/// `DoIPClient` needs to know about.
public protocol ByteTransport: Sendable {
    /// Open the connection, throwing if it cannot be established.
    func open() async throws
    /// Send raw bytes.
    func send(_ bytes: [UInt8]) async throws
    /// Receive the next chunk of bytes. May return a partial DoIP frame; the caller reassembles.
    /// Returns an empty array only transiently; throws `TransportError.closed` at end of stream.
    func receive() async throws -> [UInt8]
    /// Close and release the connection.
    func close()
}

public enum TransportError: Error, Equatable {
    case notConnected
    case closed
    case timeout
    case failed(String)
}

/// The standard DoIP TCP/UDP port (ISO 13400-2).
public let doIPPort: UInt16 = 13400
