import SwiftUI
import UniformTypeIdentifiers
import AtlasTuneCore
#if os(macOS)
import AppKit
#endif

/// Export actions. Atlas Tune exports — it never flashes. Produces a flashable BIN, a revision
/// package, or a metadata report, then hands them to the system share sheet / Files.
struct ExportMenu: View {
    @Bindable var model: WorkspaceModel
    @State private var exportURL: URL?
    @State private var showShare = false
    @State private var validation: ValidationReport?

    var body: some View {
        Menu {
            Button { export(.bin) } label: { Label("Export BIN", systemImage: "doc.badge.arrow.up") }
            Button { export(.revisionPackage) } label: { Label("Export Revision Package", systemImage: "shippingbox") }
            Button { export(.metadataReport) } label: { Label("Export Metadata Report", systemImage: "doc.text") }
            Divider()
            Button { validation = model.validate() } label: { Label("Validate", systemImage: "checkmark.shield") }
        } label: {
            Label("Export", systemImage: "square.and.arrow.up")
        }
        .disabled(model.project == nil)
        .alert("Validation", isPresented: .constant(validation != nil)) {
            Button("OK") { validation = nil }
        } message: {
            if let validation {
                Text(validation.isExportable
                     ? "Calibration is valid for export (\(validation.warnings.count) warnings)."
                     : "\(validation.errors.count) errors must be resolved before export.")
            }
        }
        #if os(iOS)
        .sheet(isPresented: $showShare) {
            if let exportURL { ShareSheet(items: [exportURL]) }
        }
        #endif
    }

    private func export(_ format: CalibrationExporter.Format) {
        guard let project = model.project else { return }
        let exporter = CalibrationExporter()
        do {
            let (data, name): (Data, String)
            switch format {
            case .bin:
                data = try exporter.exportBIN(project.workingImage)
                name = "AtlasTune.bin"
            case .revisionPackage:
                data = try exporter.exportRevisionPackage(
                    project.revisions, identity: project.identity, packageID: project.package.id)
                name = "AtlasTune.atlasrev"
            case .metadataReport:
                let report = MetadataReport(identity: project.identity, package: project.package)
                data = exporter.exportMetadataReport(report)
                name = "AtlasTune-report.txt"
            }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            try data.write(to: url)
            exportURL = url
            #if os(iOS)
            showShare = true
            #else
            // No share sheet on macOS — reveal the exported file in Finder instead.
            NSWorkspace.shared.activateFileViewerSelecting([url])
            #endif
        } catch {
            // In production this would surface a user-facing error.
        }
    }
}

#if os(iOS)
/// Thin `UIActivityViewController` bridge for sharing exported files.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
#endif
