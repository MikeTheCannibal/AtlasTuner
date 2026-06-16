import SwiftUI
import AtlasTuneCore

/// Root workspace: a three-column layout (navigator · editor · inspector) in the spirit of Final
/// Cut Pro and Xcode. Touch-first, minimal chrome, adapts to Stage Manager and external displays.
struct WorkspaceView: View {
    @State private var model = WorkspaceModel()
    @State private var showImporter = false
    @State private var columnVisibility = NavigationSplitViewVisibility.all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            navigator
                .navigationTitle("Atlas Tune")
                .navigationSplitViewColumnWidth(min: 260, ideal: 300)
        } content: {
            editor
                .navigationSplitViewColumnWidth(min: 420, ideal: 720)
        } detail: {
            InspectorView(model: model)
                .navigationSplitViewColumnWidth(min: 280, ideal: 340)
        }
        .toolbar { toolbar }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.data]) { result in
            handleImport(result)
        }
        .overlay { if model.state == .identifying { ProgressView("Identifying ROM…") } }
    }

    // MARK: Navigator

    @ViewBuilder private var navigator: some View {
        switch model.state {
        case .empty, .unrecognized:
            ContentUnavailableView {
                Label("No Calibration", systemImage: "tray.and.arrow.down")
            } description: {
                Text(model.state == .unrecognized
                     ? "This image was not recognised. Phase 1 supports BMW S58 (G87 M2)."
                     : "Import a BIN to begin.")
            } actions: {
                Button("Import BIN") { showImporter = true }
                    .buttonStyle(.borderedProminent)
            }
        default:
            CategoryNavigatorView(model: model)
        }
    }

    // MARK: Editor

    @ViewBuilder private var editor: some View {
        if let table = model.openTable {
            TableEditorContainer(model: model, table: table)
        } else if model.state == .ready {
            ContentUnavailableView("Select a Table", systemImage: "tablecells",
                                   description: Text("Choose a table from the navigator to begin editing."))
        } else {
            Color(.clear)
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarLeading) {
            Button { showImporter = true } label: { Label("Import", systemImage: "square.and.arrow.down") }
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button { model.undo() } label: { Label("Undo", systemImage: "arrow.uturn.backward") }
                .disabled(!model.canUndo)
            Button { model.redo() } label: { Label("Redo", systemImage: "arrow.uturn.forward") }
                .disabled(!model.canRedo)
            Menu {
                Button("Save Revision…") { _ = model.saveRevision(name: "Revision") }
            } label: { Label("Revisions", systemImage: "clock.arrow.circlepath") }
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        guard case let .success(url) = result else { return }
        Task {
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }
            if let data = try? Data(contentsOf: url) {
                await model.importImage(data)
            }
        }
    }
}
