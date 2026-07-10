import SwiftUI
import UniformTypeIdentifiers
import AtlasTuneCore

/// Live datalog panel: current channel readouts, start/stop, CSV export, and importing a
/// recorded MHD/bootmod3 log. The heat-map overlay it produces is consumed by the
/// spreadsheet/surface editors via the view model.
struct DatalogView: View {
    @Bindable var model: DatalogViewModel
    /// Applies a staged correction through the workspace's normal (undoable) edit path. `nil`
    /// hides the Apply buttons (e.g. no table open).
    var applyCorrection: ((SuggestedCorrection) -> Void)?
    @State private var showImporter = false
    @State private var importError: String?
    @State private var liveHost = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            liveControls
            sessionSummary
            channelGrid
            if let cell = model.activeCell {
                Label("Active cell: row \(cell.row), col \(cell.column)", systemImage: "scope")
                    .font(.callout).foregroundStyle(.tint)
            }
            atlasAI
            Spacer()
        }
        .padding()
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: [.commaSeparatedText, .plainText, .text]) { result in
            handleImport(result)
        }
        .alert("Import failed", isPresented: .constant(importError != nil)) {
            Button("OK") { importError = nil }
        } message: {
            Text(importError ?? "")
        }
    }

    private var header: some View {
        HStack {
            Text("Datalog").font(.title2.bold())
            Spacer()
            Button { showImporter = true } label: {
                Label("Import Log", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.bordered)
            .disabled(model.isLogging)
            if model.isLogging {
                Button { model.stop() } label: { Label("Stop", systemImage: "stop.fill") }
                    .buttonStyle(.borderedProminent).tint(.red)
            } else {
                Button { model.start(source: PreviewSource()) } label: {
                    Label("Demo", systemImage: "play.fill")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    /// Live connection to the car over DoIP (OBD → RJ45 → this Mac/iPad). Enter the vehicle's
    /// DoIP IP and connect; samples then stream into the same heat map / analysis pipeline.
    @ViewBuilder private var liveControls: some View {
        if model.isLogging {
            Label("Streaming live over DoIP…", systemImage: "dot.radiowaves.left.and.right")
                .font(.callout).foregroundStyle(.green)
        } else {
            HStack(spacing: 8) {
                TextField("Vehicle DoIP IP (e.g. 169.254.x.x)", text: $liveHost)
                    .textFieldStyle(.roundedBorder)
                #if os(iOS)
                    .keyboardType(.numbersAndPunctuation)
                    .autocorrectionDisabled()
                #endif
                Button { model.startLive(host: liveHost) } label: {
                    Label("Connect", systemImage: "cable.connector")
                }
                .buttonStyle(.borderedProminent)
                .disabled(liveHost.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    /// After an import, show what was loaded: sample count, duration, rate, matched channels.
    @ViewBuilder private var sessionSummary: some View {
        if !model.isLogging, model.session.sampleCount > 0 {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.session.name).font(.callout.bold()).lineLimit(1)
                Text("\(model.session.sampleCount) samples · \(model.session.duration, format: .number.precision(.fractionLength(1)))s · \(model.session.averageRate, format: .number.precision(.fractionLength(0))) Hz · \(model.session.channels.count) channels")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(Color.secondaryBackground, in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        guard case let .success(url) = result else { return }
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            try model.importCSV(data, name: url.deletingPathExtension().lastPathComponent)
        } catch let error as CSVLogImporter.ImportError {
            importError = message(for: error)
        } catch {
            importError = error.localizedDescription
        }
    }

    private func message(for error: CSVLogImporter.ImportError) -> String {
        switch error {
        case .empty: return "The file is empty or not readable text."
        case .noColumns: return "No usable channel columns were found in the header row."
        case .noDataRows: return "The file has a header but no numeric sample rows."
        }
    }

    // MARK: Atlas AI

    @ViewBuilder private var atlasAI: some View {
        if model.canAnalyze {
            Divider()
            HStack {
                Label("Atlas AI", systemImage: "sparkles").font(.headline)
                Spacer()
                Button("Analyze") { model.runAnalysis() }
                    .buttonStyle(.bordered)
            }
            if let report = model.analysis {
                atlasResults(report)
            } else {
                Text("Advisory knock / lean / boost-deviation scan of this log against the open table. Never edits your calibration.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private func atlasResults(_ report: AnalysisReport) -> some View {
        if report.isClean {
            Label("No knock, mixture, or boost issues found in \(report.analyzedSamples) samples.",
                  systemImage: "checkmark.seal")
                .font(.callout).foregroundStyle(.green)
        } else {
            if !model.corrections.isEmpty {
                correctionsList
                Divider()
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(report.findings) { finding in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: icon(finding.severity))
                                .foregroundStyle(color(finding.severity))
                            VStack(alignment: .leading, spacing: 1) {
                                Text("\(finding.category.displayName) · row \(finding.cell.row), col \(finding.cell.column)")
                                    .font(.caption.bold())
                                Text(finding.message).font(.caption2).foregroundStyle(.secondary)
                                Text(finding.suggestion).font(.caption2).foregroundStyle(.tertiary).italic()
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: 180)
            Text("Advisory only — nothing is changed until you tap Apply, and every apply is undoable.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    /// Quantified suggestions for the open table: small safe steps, one tap each to apply
    /// through the normal edit path. Re-log and re-analyze after applying to keep dialling in.
    @ViewBuilder private var correctionsList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Suggested corrections for this table").font(.caption.bold())
            ForEach(model.corrections) { correction in
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: icon(correction.severity))
                        .foregroundStyle(color(correction.severity))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(correction.summary).font(.caption)
                        if correction.stepLimited {
                            Text("Capped at one safe step — re-log after applying and analyze again.")
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                    Spacer()
                    if let applyCorrection {
                        Button("Apply") {
                            applyCorrection(correction)
                            model.markApplied(correction)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
            }
        }
    }

    private func icon(_ severity: AtlasSeverity) -> String {
        switch severity {
        case .info: return "info.circle"
        case .warning: return "exclamationmark.triangle"
        case .critical: return "exclamationmark.octagon.fill"
        }
    }

    private func color(_ severity: AtlasSeverity) -> Color {
        switch severity {
        case .info: return .secondary
        case .warning: return .orange
        case .critical: return .red
        }
    }

    private var channelGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], spacing: 8) {
            ForEach(model.session.channels) { channel in
                VStack(alignment: .leading, spacing: 2) {
                    Text(channel.name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Text(reading(channel))
                        .font(.title3.monospacedDigit().bold())
                    Text(channel.unit).font(.caption2).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color.secondaryBackground, in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private func reading(_ channel: LogChannel) -> String {
        guard let value = model.latest?.value(channel) else { return "—" }
        return String(format: "%.1f", value)
    }
}

/// A synthetic source used for previews/demos: sweeps RPM and load so the active-cell tracker
/// visibly moves across the map without hardware.
final class PreviewSource: DatalogSource, @unchecked Sendable {
    let channels = LogChannel.s58Standard
    private var task: Task<Void, Never>?

    func start() -> AsyncStream<LogSample> {
        AsyncStream { continuation in
            let task = Task {
                var t = 0.0
                while !Task.isCancelled {
                    let rpm = 1500 + 2500 * (1 + sin(t))
                    let load = 60 + 40 * (1 + cos(t * 0.7))
                    continuation.yield(LogSample(time: t, values: [
                        "rpm": rpm, "load": load, "boost": 8 + 6 * sin(t),
                        "lambda": 0.85, "ign": 10 + 5 * cos(t), "knock": 0,
                    ]))
                    t += 0.1
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
                continuation.finish()
            }
            self.task = task
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func stop() { task?.cancel() }
}
