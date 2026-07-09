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

    private var tracker: ActiveCellTracker?
    private var xChannel: LogChannel = .rpm
    private var yChannel: LogChannel = .load
    private var source: DatalogSource?
    private var task: Task<Void, Never>?

    /// Configure which table the tracker overlays and which channels drive its axes.
    func trackTable(_ table: CalibrationTable, x: LogChannel = .rpm, y: LogChannel = .load) {
        tracker = ActiveCellTracker(table: table)
        xChannel = x
        yChannel = y
        heatMap = tracker?.heatMap() ?? []
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
