import SwiftUI
import AtlasTuneCore

/// Hosts one open table and lets the tuner switch between the three rendering modes from the
/// spec: Spreadsheet, Graph (2D) and Surface (3D Metal). Carries the live cell selection and
/// the math edit toolbar.
struct TableEditorContainer: View {
    @Bindable var model: WorkspaceModel
    let table: CalibrationTable

    enum ViewMode: String, CaseIterable, Identifiable {
        case spreadsheet = "Spreadsheet"
        case graph = "Graph"
        case surface = "Surface"
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .spreadsheet: return "tablecells"
            case .graph: return "chart.xyaxis.line"
            case .surface: return "cube.transparent"
            }
        }
    }

    @State private var mode: ViewMode = .spreadsheet
    @State private var selection = CellRegion(row: 0, column: 0)
    @State private var overlayHeatMap: [[Double]]?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            EditToolbar(stats: SelectionStats.of(selection, in: table), step: nudgeStep) { operation in
                model.applyEdit(operation, region: selection)
            }
            .padding(10)
        }
        .navigationTitle(model.displayName(table.definition))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onChange(of: model.openTableID) { _, _ in
            selection = CellRegion(row: 0, column: 0)   // fresh selection per table (also re-bounds it)
        }
    }

    /// One step in the least-significant displayed digit (e.g. 0.1 for a 1-decimal table),
    /// so the ± buttons nudge by a natural increment for this map.
    private var nudgeStep: Double {
        let decimals = table.definition.scaling.decimals
        return decimals <= 0 ? 1 : pow(10, -Double(decimals))
    }

    private var header: some View {
        HStack {
            Picker("View", selection: $mode) {
                ForEach(availableModes) { m in
                    Label(m.rawValue, systemImage: m.symbol).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 360)
            Spacer()
            Text(table.definition.unit)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
        }
        .padding(8)
    }

    @ViewBuilder private var content: some View {
        switch mode {
        case .spreadsheet:
            SpreadsheetView(table: table, selection: $selection, heatMap: overlayHeatMap,
                            zoomBinding: zoomBinding)
        case .graph:
            TableGraphView(table: table)
        case .surface:
            SurfaceContainerView(table: table)
        }
    }

    /// Zoom routed to the workspace so each map keeps its own level across switches/relaunches.
    private var zoomBinding: Binding<Double> {
        let id = table.definition.id
        return Binding(get: { model.zoom(for: id) },
                       set: { model.setZoom($0, for: id) })
    }

    /// Graph is most useful for 1D, surface for 3D — but all modes stay available.
    private var availableModes: [ViewMode] {
        switch table.definition.dimensionality {
        case .scalar, .oneD: return [.spreadsheet, .graph]
        default: return ViewMode.allCases
        }
    }
}
