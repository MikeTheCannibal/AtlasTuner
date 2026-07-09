import SwiftUI
import AtlasTuneCore

/// Live datalog panel: current channel readouts plus start/stop and CSV export. The heat-map
/// overlay it produces is consumed by the spreadsheet/surface editors via the view model.
struct DatalogView: View {
    @Bindable var model: DatalogViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            channelGrid
            if let cell = model.activeCell {
                Label("Active cell: row \(cell.row), col \(cell.column)", systemImage: "scope")
                    .font(.callout).foregroundStyle(.tint)
            }
            Spacer()
        }
        .padding()
    }

    private var header: some View {
        HStack {
            Text("Datalog").font(.title2.bold())
            Spacer()
            Button {
                model.isLogging ? model.stop() : model.start(source: PreviewSource())
            } label: {
                Label(model.isLogging ? "Stop" : "Start",
                      systemImage: model.isLogging ? "stop.fill" : "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(model.isLogging ? .red : .green)
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
