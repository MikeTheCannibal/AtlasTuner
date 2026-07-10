import SwiftUI
import UniformTypeIdentifiers
import AtlasTuneCore

/// In-app DID-map reconciliation. Walks the user through the read-only steps — scan the car,
/// capture a drive, correlate against an MHD log — and applies the recovered map to live logging.
/// Presented as a sheet from the datalog panel; drives the `AtlasTuneCore` reconciliation engine.
struct DIDReconcileView: View {
    @Bindable var model: DIDReconcileModel
    /// Adopt the reconciled map for live logging.
    let onApply: (LiveChannelSet) -> Void
    let onClose: () -> Void

    @State private var showCaptureImporter = false
    @State private var showReferenceImporter = false
    @State private var showExporter = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Reconcile DID Map").font(.title2.bold())
                Spacer()
                Button("Done") { onClose() }
            }
            .padding()
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    intro
                    step1Scan
                    step2Capture
                    step3Reconcile
                    if !model.candidates.isEmpty { results }
                }
                .padding()
            }
        }
        .frame(minWidth: 480, minHeight: 560)
        .fileImporter(isPresented: $showCaptureImporter,
                      allowedContentTypes: [.commaSeparatedText, .plainText, .text]) { handleCapture($0) }
        .fileImporter(isPresented: $showReferenceImporter,
                      allowedContentTypes: [.commaSeparatedText, .plainText, .text]) { handleReference($0) }
        .fileExporter(isPresented: $showExporter, document: channelSetDocument(),
                      contentType: .json, defaultFilename: "live_channels") { _ in }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Recover the real S58 live-data map from the car, read-only.")
                .font(.callout)
            Text("Scanning and capture only ever read (UDS 0x22) — nothing is written to the ECU. "
                 + "MHD runs on your phone and the cable feeds this Mac, so record the capture and the "
                 + "MHD log as two separate drives of the same routine; they're aligned on their shared RPM trace.")
                .font(.caption).foregroundStyle(.secondary)
            if case let .failed(message) = model.phase {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.red)
            }
        }
    }

    // MARK: Step 1 — scan

    private var step1Scan: some View {
        stepCard(number: 1, title: "Scan for responding DIDs") {
            HStack(spacing: 8) {
                TextField("Vehicle DoIP IP (e.g. 169.254.x.x)", text: $model.host)
                    .textFieldStyle(.roundedBorder)
                #if os(iOS)
                    .keyboardType(.numbersAndPunctuation).autocorrectionDisabled()
                #endif
                Button { model.scan() } label: { Label("Scan", systemImage: "dot.radiowaves.left.and.right") }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.host.trimmingCharacters(in: .whitespaces).isEmpty || model.isBusy)
            }
            switch model.phase {
            case let .scanning(current, found):
                progress("Scanning 0x\(String(current, radix: 16))… \(found) found")
            case let .scanned(count):
                Label("\(count) responding DIDs.", systemImage: "checkmark.circle").foregroundStyle(.green).font(.caption)
            default:
                if !model.probes.isEmpty {
                    Text("\(model.probes.count) responders found.").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: Step 2 — capture

    private var step2Capture: some View {
        stepCard(number: 2, title: "Capture a drive") {
            HStack(spacing: 8) {
                Text("Duration").font(.caption)
                TextField("seconds", value: $model.captureSeconds, format: .number)
                    .textFieldStyle(.roundedBorder).frame(width: 70)
                #if os(iOS)
                    .keyboardType(.numberPad)
                #endif
                Text("s").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { model.captureFoundDIDs() } label: { Label("Capture", systemImage: "record.circle") }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.probes.isEmpty || model.isBusy)
                Button("Import…") { showCaptureImporter = true }.buttonStyle(.bordered).disabled(model.isBusy)
            }
            switch model.phase {
            case let .capturing(elapsed):
                HStack {
                    progress(String(format: "Recording… %.0f/%.0fs", elapsed, model.captureSeconds))
                    Button("Stop") { model.cancel() }.buttonStyle(.bordered).controlSize(.small)
                }
            case let .captured(dids):
                Label("Captured \(dids) DID series.", systemImage: "checkmark.circle").foregroundStyle(.green).font(.caption)
            default:
                if !model.capture.isEmpty {
                    Text("\(model.capture.count) DID series ready.").font(.caption).foregroundStyle(.secondary)
                }
            }
            Text("Drive a repeatable routine of held steady-states (idle, hold 2000/3000/4000 rpm, part- then near-WOT), not quick sweeps — steady points reproduce across the two drives.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    // MARK: Step 3 — reconcile

    private var step3Reconcile: some View {
        stepCard(number: 3, title: "Correlate against an MHD log") {
            HStack(spacing: 8) {
                Button { showReferenceImporter = true } label: {
                    Label(model.reference == nil ? "Choose MHD log…" : "MHD log loaded", systemImage: "doc.badge.plus")
                }
                .buttonStyle(.bordered)
                Button { model.reconcile() } label: { Label("Reconcile", systemImage: "wand.and.stars") }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.reference == nil || model.capture.isEmpty || model.isBusy)
            }
            if let reference = model.reference {
                Text("Reference: \(reference.channels.count) channels, \(reference.sampleCount) samples.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Results

    private var results: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Recovered map").font(.headline)
                Spacer()
                Button { showExporter = true } label: { Label("Export JSON", systemImage: "square.and.arrow.up") }
                    .buttonStyle(.bordered).controlSize(.small)
                Button {
                    onApply(model.confidentChannelSet)
                    onClose()
                } label: { Label("Apply \(model.confidentChannelSet.identifiers.count) channels", systemImage: "checkmark.seal") }
                    .buttonStyle(.borderedProminent).controlSize(.small)
                    .disabled(model.confidentChannelSet.identifiers.isEmpty)
            }
            ForEach(model.candidates, id: \.channel.id) { c in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: c.isConfident ? "checkmark.circle.fill" : "questionmark.circle")
                        .foregroundStyle(c.isConfident ? .green : .orange)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(c.channel.name) → DID 0x\(String(format: "%04X", c.did))").font(.caption.bold())
                        Text(String(format: "raw × %.5g %+.4g %@ · r=%.3f (next %.3f) · lag %+.2fs",
                                    c.scaling.factor, c.scaling.offset, c.channel.unit,
                                    c.correlation, c.runnerUpCorrelation, c.appliedLag))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
            Text("Only confident matches (strong correlation with a clear margin over the runner-up) are applied. Verify readings against the car before trusting a tune to them.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    // MARK: Building blocks

    private func stepCard<Content: View>(number: Int, title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("\(number)").font(.caption.bold()).frame(width: 20, height: 20)
                    .background(Circle().fill(.tint.opacity(0.2)))
                Text(title).font(.headline)
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.secondaryBackground, in: RoundedRectangle(cornerRadius: 12))
    }

    private func progress(_ text: String) -> some View {
        HStack(spacing: 6) {
            ProgressView().controlSize(.small)
            Text(text).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func channelSetDocument() -> JSONDocument {
        JSONDocument(data: (try? model.exportedChannelSet()) ?? Data())
    }

    private func handleCapture(_ result: Result<URL, Error>) {
        readSecurityScoped(result) { try model.loadCapture($0) }
    }

    private func handleReference(_ result: Result<URL, Error>) {
        readSecurityScoped(result) { try model.loadReference($0, name: "MHD reference") }
    }

    private func readSecurityScoped(_ result: Result<URL, Error>, _ body: (Data) throws -> Void) {
        guard case let .success(url) = result else { return }
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        if let data = try? Data(contentsOf: url) { try? body(data) }
    }
}

/// Minimal `FileDocument` wrapper so the recovered map exports through the system file exporter.
struct JSONDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
