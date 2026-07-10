import Foundation
import Observation
import AtlasTuneCore

/// Drives a live datalog session and, when a table is open, the flagship active-cell tracker.
/// Samples flow in from any `DatalogSource`; the view model maps the configured X/Y channels onto
/// the open table's axes to light up the active cell and accumulate the heat map.
@MainActor
@Observable
final class DatalogViewModel {
    private(set) var session = LogSession(name: "Live Session")
    private(set) var latest: LogSample?
    private(set) var isLogging = false

    /// Heat map (0..1) aligned to the tracked table's cells.
    private(set) var heatMap: [[Double]] = []
    private(set) var activeCell: CellAddress?
    private(set) var recentCells: [CellAddress] = []

    /// Latest Atlas AI advisory report for the loaded session against the tracked table.
    private(set) var analysis: AnalysisReport?
    /// Quantified, safety-clamped suggestions applicable to the tracked table. Applying one is
    /// always an explicit user action routed through the normal (undoable) edit path.
    private(set) var corrections: [SuggestedCorrection] = []

    private var tracker: ActiveCellTracker?
    private var trackedTable: CalibrationTable?
    private var xChannel: LogChannel = .rpm
    private var yChannel: LogChannel = .load
    private var source: DatalogSource?
    private var task: Task<Void, Never>?

    /// Configure which table the tracker overlays and which channels drive its axes.
    func trackTable(_ table: CalibrationTable, x: LogChannel = .rpm, y: LogChannel = .load) {
        tracker = ActiveCellTracker(table: table)
        trackedTable = table
        xChannel = x
        yChannel = y
        heatMap = tracker?.heatMap() ?? []
        analysis = nil
        corrections = []
    }

    /// Whether an Atlas AI analysis can run (a session is loaded and a table is being tracked).
    var canAnalyze: Bool { trackedTable != nil && session.sampleCount > 0 }

    /// Run Atlas AI over the loaded session against the tracked table. Advisory only — it never
    /// edits anything; the result is exposed via `analysis`/`corrections`.
    func runAnalysis(thresholds: AtlasAI.Thresholds = .init()) {
        guard let trackedTable else { return }
        let report = AtlasAI(thresholds: thresholds).analyze(session, table: trackedTable, x: xChannel, y: yChannel)
        analysis = report
        corrections = CorrectionEngine(thresholds: thresholds).corrections(for: report, table: trackedTable)
    }

    /// Drop a suggestion once the user has applied it, so it isn't applied twice; the next
    /// analysis pass (on fresh data) recomputes from scratch.
    func markApplied(_ correction: SuggestedCorrection) {
        corrections.removeAll { $0.id == correction.id }
    }

    /// Refresh the tracked table's values after an edit without discarding the current
    /// analysis or the remaining (unapplied) suggestions.
    func refreshTrackedTable(_ table: CalibrationTable) {
        trackedTable = table
    }

    func start(source: DatalogSource) {
        guard !isLogging else { return }
        self.source = source
        session = LogSession(name: "Live Session", channels: source.channels)
        isLogging = true
        let stream = source.start()
        task = Task { [weak self] in
            for await sample in stream {
                await self?.ingest(sample)
            }
            await MainActor.run { self?.isLogging = false }
        }
    }

    /// Connect to a live vehicle over DoIP (Ethernet/RJ45 from the OBD port) and stream samples
    /// through the same pipeline as a replayed log — the heat map and active-cell tracker update
    /// live. `host` is the DoIP entity's IP; `port` defaults to the ISO 13400 standard 13400.
    func startLive(host: String, port: UInt16 = doIPPort, channelSet: LiveChannelSet = .s58Placeholder) {
        let transport = TCPByteTransport(host: host, port: port)
        start(source: LiveDatalogSource(transport: transport, channelSet: channelSet))
    }

    func stop() {
        task?.cancel()
        source?.stop()
        isLogging = false
    }

    /// Load a recorded session (e.g. an imported MHD/bootmod3 CSV) and replay it through the
    /// active-cell tracker in one pass, so the heat map and recent-cell trail populate immediately.
    func loadSession(_ session: LogSession) {
        stop()
        self.session = session
        latest = session.samples.last
        analysis = nil
        corrections = []
        guard var tracker else { return }
        tracker.reset()
        tracker.record(session: session, x: xChannel, y: yChannel)
        activeCell = tracker.current
        heatMap = tracker.heatMap()
        recentCells = tracker.recentCells(12)
        self.tracker = tracker
    }

    /// Parse a datalog CSV and load it. Throws `CSVLogImporter.ImportError` on malformed input.
    func importCSV(_ data: Data, name: String) throws {
        let session = try CSVLogImporter().session(from: data, name: name)
        loadSession(session)
    }

    private func ingest(_ sample: LogSample) {
        session.append(sample)
        latest = sample
        guard var tracker,
              let x = sample.value(xChannel) else { return }
        let y = sample.value(yChannel)
        activeCell = tracker.record(x: x, y: y)
        heatMap = tracker.heatMap()
        recentCells = tracker.recentCells(12)
        self.tracker = tracker
    }

    func exportCSV() -> Data {
        CSVExporter().data(for: session)
    }
}
