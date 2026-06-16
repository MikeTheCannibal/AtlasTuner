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
        // This Task inherits the @MainActor context, so `ingest` and the state update below are
        // same-actor (synchronous) calls — only the async stream iteration needs `await`.
        task = Task { [weak self] in
            for await sample in stream {
                self?.ingest(sample)
            }
            self?.isLogging = false
        }
    }

    func stop() {
        task?.cancel()
        source?.stop()
        isLogging = false
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
