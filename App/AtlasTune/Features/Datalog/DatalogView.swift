import SwiftUI
import UniformTypeIdentifiers
import AtlasTuneCore

/// Live datalog panel: data source controls, current channel readouts, the active cell, and a raw
/// sample table. The built-in "Demo" source is a simulated signal; real drive data comes in by
/// importing a CSV log, which can then be replayed to animate the heat map.
struct DatalogView: View {
    @Bindable var model: DatalogViewModel

    @State private var showImporter = false
    @State private var showRaw = false
    @State private var shareItem: ShareItem?

    private struct ShareItem: Identifiable { let id = UUID(); let url: URL }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            sourceCaption
            channelGrid
            if let cell = model.activeCell {
                Label("Active cell: row \(cell.row), col \(cell.column)", systemImage: "scope")
                    .font(.callout).foregroundStyle(.tint)
            }
            rawDataDisclosure
            Spacer(minLength: 0)
        }
        .padding()
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: [.commaSeparatedText, .plainText, .text]) { result in
            handleImport(result)
        }
        .sheet(item: $shareItem) { item in ShareSheet(items: [item.url]) }
    }

    // MARK: Header & controls

    private var header: some View {
        HStack {
            Text("Datalog").font(.title2.bold())
            Spacer()
            Button { showImporter = true } label: {
                Label("Import Log", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.bordered)

            if !model.session.samples.isEmpty, !model.isLogging {
                Button { model.replayLoaded() } label: {
                    Label("Replay", systemImage: "memories")
                }
                .buttonStyle(.bordered)
            }

            Button {
                model.isLogging ? model.stop() : model.start(source: PreviewSource())
            } label: {
                Label(model.isLogging ? "Stop" : "Demo",
                      systemImage: model.isLogging ? "stop.fill" : "waveform.path.ecg")
            }
            .buttonStyle(.borderedProminent)
            .tint(model.isLogging ? .red : .green)

            Button {
                if let url = model.exportCSVFile() { shareItem = ShareItem(url: url) }
            } label: {
                Label("Share CSV", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.bordered)
            .disabled(model.session.samples.isEmpty)
        }
    }

    private var sourceCaption: some View {
        HStack(spacing: 6) {
            Image(systemName: "info.circle")
            Text(captionText)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var captionText: String {
        if model.isLogging {
            return "Streaming “\(model.session.name)” · \(model.session.sampleCount) samples"
        }
        if model.session.samples.isEmpty {
            return "No data yet. “Demo” plays a simulated signal; “Import Log” loads a real CSV datalog."
        }
        return "“\(model.session.name)” · \(model.session.sampleCount) samples · "
             + String(format: "%.0f Hz avg", model.session.averageRate)
    }

    // MARK: Live readouts

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
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private func reading(_ channel: LogChannel) -> String {
        guard let value = model.latest?.value(channel) else { return "—" }
        return String(format: "%.1f", value)
    }

    // MARK: Raw data

    @ViewBuilder private var rawDataDisclosure: some View {
        if !model.session.samples.isEmpty {
            HStack {
                Text("Raw Data").font(.headline)
                Text("\(model.session.sampleCount) rows").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(showRaw ? "Hide" : "Show") { withAnimation { showRaw.toggle() } }
            }
            if showRaw {
                RawDataTableView(session: model.session)
                    .frame(maxHeight: 360)
            }
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        guard case let .success(url) = result else { return }
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }
        if let data = try? Data(contentsOf: url) {
            model.importCSV(data, name: url.deletingPathExtension().lastPathComponent)
        }
    }
}

/// A scrollable spreadsheet of the raw samples (time + every channel). Lazy in both axes so large
/// logs stay smooth.
struct RawDataTableView: View {
    let session: LogSession
    private let columnWidth: CGFloat = 84

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    ForEach(Array(session.samples.enumerated()), id: \.offset) { _, sample in
                        row(sample)
                    }
                } header: {
                    headerRow
                }
            }
            .font(.caption.monospacedDigit())
        }
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
    }

    private var headerRow: some View {
        HStack(spacing: 0) {
            cell("time", width: 64, bold: true)
            ForEach(session.channels) { cell($0.id, width: columnWidth, bold: true) }
        }
        .background(Color(.tertiarySystemBackground))
    }

    private func row(_ sample: LogSample) -> some View {
        HStack(spacing: 0) {
            cell(String(format: "%.2f", sample.time), width: 64)
            ForEach(session.channels) { channel in
                cell(sample.value(channel).map { String(format: "%.2f", $0) } ?? "—", width: columnWidth)
            }
        }
    }

    private func cell(_ text: String, width: CGFloat, bold: Bool = false) -> some View {
        Text(text)
            .fontWeight(bold ? .semibold : .regular)
            .foregroundStyle(bold ? .secondary : .primary)
            .frame(width: width, alignment: .trailing)
            .padding(.vertical, 3).padding(.horizontal, 4)
            .lineLimit(1)
    }
}

/// A synthetic source used for previews/demos: sweeps RPM and load so the active-cell tracker
/// visibly moves across the map without hardware. This is NOT vehicle data.
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
