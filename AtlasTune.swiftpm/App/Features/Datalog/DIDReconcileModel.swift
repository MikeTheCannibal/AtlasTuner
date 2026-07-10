import Foundation
import Observation
import AtlasTuneCore

/// Drives the in-app DID-map reconciliation flow: scan the car for responding DIDs, capture their
/// raw values over a drive, then correlate that capture against a labelled MHD/bootmod3 log to
/// recover the real S58 DID map. All read-only on the car (only `ReadDataByIdentifier`, 0x22); the
/// reconcile step is pure and offline. Built into the app so the end user never touches a separate
/// tool or runtime — it drives the same `AtlasTuneCore` reconciliation engine end to end.
@MainActor
@Observable
final class DIDReconcileModel {
    enum Phase: Equatable {
        case idle
        case scanning(current: UInt16, found: Int)
        case scanned(count: Int)
        case capturing(elapsed: TimeInterval)
        case captured(dids: Int)
        case reconciled(confident: Int, total: Int)
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    var host = ""
    var scanLow: UInt16 = 0xF400
    var scanHigh: UInt16 = 0xF4FF
    var captureSeconds: Double = 60

    private(set) var probes: [DIDProbe] = []
    private(set) var capture: [CapturedDID] = []
    private(set) var candidates: [ChannelCandidate] = []
    private(set) var reference: LogSession?

    /// Injectable so tests drive the flow against an in-memory ECU instead of a real socket.
    private let transportFactory: (String, UInt16) -> ByteTransport
    private var task: Task<Void, Never>?

    init(transportFactory: @escaping (String, UInt16) -> ByteTransport = { TCPByteTransport(host: $0, port: $1) }) {
        self.transportFactory = transportFactory
    }

    var isBusy: Bool {
        switch phase {
        case .scanning, .capturing: return true
        default: return false
        }
    }

    private func makeClient() -> DoIPClient {
        DoIPClient(transport: transportFactory(host.trimmingCharacters(in: .whitespaces), doIPPort))
    }

    // MARK: Car-side steps (read-only)

    func scan() {
        guard !host.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        phase = .scanning(current: scanLow, found: 0)
        let scanner = DIDScanner(client: makeClient())
        let range = scanLow...scanHigh
        task = Task { [weak self] in
            do {
                let found = try await scanner.scan(range: range) { did, count in
                    Task { @MainActor in
                        if case .scanning = self?.phase { self?.phase = .scanning(current: did, found: count) }
                    }
                }
                self?.probes = found
                self?.phase = .scanned(count: found.count)
            } catch {
                self?.phase = .failed(Self.message(error))
            }
        }
    }

    func capture(dids: [UInt16]) {
        guard !dids.isEmpty else { return }
        phase = .capturing(elapsed: 0)
        let recorder = DIDCapture(client: makeClient())
        let seconds = captureSeconds
        task = Task { [weak self] in
            do {
                let series = try await recorder.record(dids: dids, duration: seconds) { t in
                    Task { @MainActor in self?.phase = .capturing(elapsed: t) }
                }
                self?.capture = series
                self?.phase = .captured(dids: series.count)
            } catch {
                self?.phase = .failed(Self.message(error))
            }
        }
    }

    /// Capture every DID the scan found.
    func captureFoundDIDs() { capture(dids: probes.map(\.did)) }

    func cancel() {
        task?.cancel()
        task = nil
        if isBusy { phase = .idle }
    }

    // MARK: Offline import (capture / reference can come from earlier drives or files)

    func loadCapture(_ data: Data) throws {
        guard let text = String(data: data, encoding: .utf8) else { throw DIDCaptureFile.ParseError.noHeader }
        capture = try DIDCaptureFile.parse(text)
        phase = .captured(dids: capture.count)
    }

    func loadReference(_ data: Data, name: String) throws {
        reference = try CSVLogImporter().session(from: data, name: name)
    }

    // MARK: Reconcile (pure, offline)

    /// Correlate the capture against the reference MHD log and rank the resulting candidates.
    func reconcile() {
        guard let reference, !capture.isEmpty else { return }
        candidates = DIDReconciler().reconcile(capture: capture, reference: reference)
        let confident = candidates.filter(\.isConfident).count
        phase = .reconciled(confident: confident, total: candidates.count)
    }

    var confidentChannelSet: LiveChannelSet {
        LiveChannelSet(identifiers: candidates.filter(\.isConfident).map(\.identifier))
    }

    /// Serialised confident map for export/backup.
    func exportedChannelSet() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(confidentChannelSet)
    }

    private static func message(_ error: Error) -> String {
        if let t = error as? TransportError {
            switch t {
            case .notConnected, .closed: return "Lost the connection to the vehicle."
            case .timeout: return "The vehicle didn't respond in time. Check the cable and DoIP IP."
            case .failed(let d): return "Connection failed: \(d)"
            }
        }
        return "\(error)"
    }
}
