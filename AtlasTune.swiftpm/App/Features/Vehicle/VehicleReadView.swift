import SwiftUI
import AtlasTuneCore

/// "Read ROM from Vehicle" flow: connect over ENET, download a 1:1 copy of the running calibration
/// with progress, then verify it against the working file and offer to open or keep it for compare.
struct VehicleReadView: View {
    @Bindable var model: WorkspaceModel
    @Environment(\.dismiss) private var dismiss

    @AppStorage("atlas.enet.host") private var host = "169.254.187.20"
    @AppStorage("atlas.enet.port") private var port = 13400
    @AppStorage("atlas.enet.flashBase") private var flashBaseHex = "0x80000000"

    enum Phase: Equatable {
        case idle
        case reading(Double)
        case done
        case failed(String)
    }

    @State private var phase: Phase = .idle
    @State private var image: BINImage?
    @State private var comparison: WorkspaceModel.VehicleComparison?
    @State private var reader: VehicleROMReader?

    var body: some View {
        NavigationStack {
            Form {
                connectionSection
                statusSection
                if phase == .done, let image { resultSection(image) }
                cautionSection
            }
            .navigationTitle("Read ROM from Vehicle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { reader?.cancel(); dismiss() }
                }
            }
        }
    }

    // MARK: Sections

    @ViewBuilder private var connectionSection: some View {
        Section("Gateway") {
            LabeledContent("Host") {
                TextField("169.254.x.x", text: $host)
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
            }
            LabeledContent("Port") {
                TextField("13400", value: $port, format: .number.grouping(.never))
                    .multilineTextAlignment(.trailing).keyboardType(.numberPad)
            }
            LabeledContent("Flash base") {
                TextField("0x80000000", text: $flashBaseHex)
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
            }
        }
        .disabled(isReading)
    }

    @ViewBuilder private var statusSection: some View {
        Section {
            switch phase {
            case .idle:
                Button {
                    startRead()
                } label: {
                    Label("Download ROM", systemImage: "arrow.down.circle")
                }
            case .reading(let fraction):
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: fraction) {
                        Text("Reading… \(Int(fraction * 100))%")
                    }
                    Button("Cancel", role: .destructive) { reader?.cancel(); phase = .idle }
                }
            case .done:
                Label("Download complete", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .failed(let message):
                VStack(alignment: .leading, spacing: 6) {
                    Label("Read failed", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(message).font(.footnote).foregroundStyle(.secondary)
                    Button("Try Again") { phase = .idle }
                }
            }
        }
    }

    @ViewBuilder private func resultSection(_ image: BINImage) -> some View {
        if let comparison {
            Section("Verify vs Working File") {
                if comparison.matches {
                    Label("Your working file matches the vehicle exactly.", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                } else {
                    Label("Different from your working file.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    if let diff = comparison.difference {
                        LabeledContent("Changed tables", value: "\(diff.changedTables.count)")
                        LabeledContent("Changed cells", value: "\(diff.totalChangedCells)")
                    }
                }
            }
        }
        Section("Use This Copy") {
            Button {
                Task { await model.openImage(image); dismiss() }
            } label: { Label("Open as New Project", systemImage: "doc.badge.plus") }

            if model.project != nil {
                Button {
                    model.addVehicleReference(image, name: "Vehicle \(Date().formatted(date: .abbreviated, time: .shortened))")
                    dismiss()
                } label: { Label("Keep as Reference for Compare", systemImage: "square.on.square") }
            }
        }
    }

    private var cautionSection: some View {
        Section {
            Text("Downloads a 1:1 copy of the calibration over DoIP/UDS (read-only — nothing is written to the ECU). Reading protected flash requires a security unlock; the S58 seed/key is not bundled. Addresses depend on the software build — confirm the flash base for your vehicle.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    // MARK: Logic

    private var isReading: Bool {
        if case .reading = phase { return true }
        return false
    }

    private func startRead() {
        let base = UInt32(flashBaseHex.replacingOccurrences(of: "0x", with: ""), radix: 16) ?? 0x8000_0000
        let reader = VehicleROMReader(host: host, port: UInt16(clamping: port),
                                      layout: .s58(flashBase: base))
        self.reader = reader
        phase = .reading(0)
        Task {
            do {
                for try await event in reader.read() {
                    switch event {
                    case .progress(let fraction, _, _):
                        phase = .reading(fraction)
                    case .completed(let downloaded):
                        image = downloaded
                        comparison = model.compareWorking(against: downloaded)
                        phase = .done
                    }
                }
            } catch {
                phase = .failed(Self.describe(error))
            }
        }
    }

    private static func describe(_ error: Error) -> String {
        if let readError = error as? VehicleROMReader.ReadError {
            switch readError {
            case .accessDenied(let nrc):
                return "The ECU refused the read (NRC 0x\(String(nrc, radix: 16))). This region likely needs a security unlock, which isn't bundled."
            case .securityFailed:
                return "Security access failed. A valid S58 seed/key provider is required to read protected flash."
            case .incompleteRead:
                return "The read did not return all expected bytes."
            }
        }
        return error.localizedDescription
    }
}
