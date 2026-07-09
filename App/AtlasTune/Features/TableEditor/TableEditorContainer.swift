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
            EditToolbar { operation in
                model.applyEdit(operation, region: selection)
            }
            .padding(8)
        }
        .navigationTitle(table.definition.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
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
            SpreadsheetView(table: table, selection: $selection, heatMap: overlayHeatMap)
        case .graph:
            TableGraphView(table: table)
        case .surface:
            SurfaceContainerView(table: table)
        }
    }

    /// Graph is most useful for 1D, surface for 3D — but all modes stay available.
    private var availableModes: [ViewMode] {
        switch table.definition.dimensionality {
        case .scalar, .oneD: return [.spreadsheet, .graph]
        default: return ViewMode.allCases
        }
    }
}
