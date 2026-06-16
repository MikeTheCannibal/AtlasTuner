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

    /// Configure which table the tracker overlays and which channels drive its axes. Rebuilds the
    /// heat map over any samples already loaded, so opening a table after importing a log still
    /// lights up where the car spent its time.
    func trackTable(_ table: CalibrationTable, x: LogChannel = .rpm, y: LogChannel = .load) {
        tracker = ActiveCellTracker(table: table)
        xChannel = x
        yChannel = y
        rebuildTrackerFromSession()
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

    // MARK: Recorded logs

    /// Load a recorded session statically: the raw table and full heat map populate immediately,
    /// no streaming.
    func loadSession(_ session: LogSession) {
        stop()
        self.session = session
        latest = session.samples.last
        rebuildTrackerFromSession()
    }

    /// Import a CSV log (round-trips with the exporter; also accepts generic logs) and load it.
    @discardableResult
    func importCSV(_ data: Data, name: String) -> Bool {
        guard let session = try? CSVImporter().session(from: data, name: name) else { return false }
        loadSession(session)
        return true
    }

    /// Re-stream the currently loaded session through `ReplayDatalogSource` so the active cell
    /// animates across the map at `rate` Hz.
    func replayLoaded(rate: Double = 60) {
        guard !session.samples.isEmpty else { return }
        let replay = session
        start(source: ReplayDatalogSource(session: replay, rate: rate))
    }

    /// Recompute the tracker/heat map from every sample in the current session.
    private func rebuildTrackerFromSession() {
        guard var tracker else { heatMap = []; return }
        tracker.reset()
        for sample in session.samples {
            guard let x = sample.value(xChannel) else { continue }
            tracker.record(x: x, y: sample.value(yChannel))
        }
        self.tracker = tracker
        heatMap = tracker.heatMap()
        activeCell = tracker.current
        recentCells = tracker.recentCells(12)
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

    /// Write the current session to a temporary CSV file for sharing; returns its URL.
    func exportCSVFile() -> URL? {
        let safeName = session.name.replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(safeName).csv")
        do {
            try exportCSV().write(to: url)
            return url
        } catch {
            return nil
        }
    }
}
