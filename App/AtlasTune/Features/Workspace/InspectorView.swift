import SwiftUI
import AtlasTuneCore

/// Right-hand inspector with three tabs: table info, revision history, and the live datalog. Kept
/// in the detail column so it stays visible alongside the editor in Stage Manager layouts.
struct InspectorView: View {
    @Bindable var model: WorkspaceModel
    @State private var datalog = DatalogViewModel()
    @State private var tab: Tab = .info

    enum Tab: String, CaseIterable, Identifiable {
        case info = "Info", revisions = "Revisions", datalog = "Datalog"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Inspector", selection: $tab) {
                ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(8)
            Divider()
            content
        }
        .onChange(of: model.openTableID) { _, _ in
            if let table = model.openTable { datalog.trackTable(table) }
        }
    }

    @ViewBuilder private var content: some View {
        switch tab {
        case .info: infoTab
        case .revisions: RevisionListView(model: model)
        case .datalog: DatalogView(model: datalog)
        }
    }

    @ViewBuilder private var infoTab: some View {
        if let table = model.openTable {
            List {
                TableAboutView(model: model, table: table.definition)
                Section("Table") {
                    labeled("Name", model.displayName(table.definition))
                    labeled("Category", table.definition.category.displayName)
                    labeled("Units", table.definition.unit)
                    labeled("Size", "\(table.rows) × \(table.columns)")
                    if let range = table.definition.valueRange {
                        labeled("Safe Range", "\(range.lowerBound) … \(range.upperBound)")
                    }
                }
                if !table.definition.description.isEmpty {
                    Section("Description") {
                        Text(model.translationEnabled
                             ? model.glossary.translate(table.definition.description)
                             : table.definition.description)
                    }
                }
                Section("Calibration") {
                    labeled("ROM", model.identity?.family ?? "—")
                    labeled("Version", model.identity?.calibrationVersion ?? "—")
                }
                Section { ExportMenu(model: model) }
            }
        } else if let identity = model.identity {
            List {
                Section("Calibration") {
                    labeled("ROM", identity.family)
                    labeled("Version", identity.calibrationVersion)
                    labeled("Confidence", String(format: "%.0f%%", identity.confidence * 100))
                }
                Section { ExportMenu(model: model) }
            }
        } else {
            ContentUnavailableView("No Selection", systemImage: "info.circle")
        }
    }

    private func labeled(_ title: String, _ value: String) -> some View {
        LabeledContent(title, value: value)
    }
}
