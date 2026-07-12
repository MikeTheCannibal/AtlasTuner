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
        case .datalog:
            DatalogView(model: datalog, applyCorrection: model.openTable == nil ? nil : { correction in
                model.applyEdit(correction.operation, region: correction.region)
                // Keep the tracked table current without discarding remaining suggestions.
                if let table = model.openTable { datalog.refreshTrackedTable(table) }
            })
        }
    }

    @ViewBuilder private var infoTab: some View {
        if let table = model.openTable {
            List {
                Section("Table") {
                    labeled("Name", model.displayName(table.definition))
                    if model.translateNames, table.definition.name != model.displayName(table.definition) {
                        labeled("Original", table.definition.name)
                    }
                    labeled("Category", table.definition.category.displayName)
                    labeled("Units", table.definition.unit)
                    labeled("Size", "\(table.rows) × \(table.columns)")
                    if let range = table.definition.valueRange {
                        labeled("Safe Range", "\(range.lowerBound) … \(range.upperBound)")
                    }
                }
                aboutSection(table.definition)
                if !table.definition.description.isEmpty {
                    Section("Description") { Text(table.definition.description) }
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

    /// "About this map": an immediate offline explanation of what the table does, plus a
    /// user-initiated web search (opens the browser — we link out rather than reproduce third-party
    /// content in-app).
    @ViewBuilder private func aboutSection(_ definition: TableDefinition) -> some View {
        let explanation = MapExplainer().builtinExplanation(for: definition)
        Section("About this map") {
            Text(explanation.summary).font(.callout)
            if let note = explanation.tuningNote {
                Label(note, systemImage: "wrench.and.screwdriver")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let url = webSearchURL(for: definition) {
                Link(destination: url) {
                    Label("Look up online", systemImage: "safari")
                }
            }
        }
        if let article = MG1TuningKnowledge.article(for: definition) {
            mg1Section(article)
        }
    }

    /// Curated MG1 systems knowledge for the map's control chain: how it works, ordered practice,
    /// the sharp edge, and the source guide.
    @ViewBuilder private func mg1Section(_ article: MG1KnowledgeArticle) -> some View {
        Section("MG1: \(article.title)") {
            Text(article.howItWorks).font(.callout)
            ForEach(Array(article.practice.enumerated()), id: \.offset) { index, step in
                Label(step, systemImage: "\(index + 1).circle")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let warning = article.warning {
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }
            if !article.logChannels.isEmpty {
                Button {
                    datalog.watch(article.logChannels)
                    tab = .datalog
                } label: {
                    Label("Watch in Datalog: \(article.logChannels.map(\.name).joined(separator: ", "))",
                          systemImage: "waveform.path.ecg")
                        .font(.caption)
                }
                .help("Pin these channels to the top of the datalog panel")
            }
            Link(destination: article.reference) {
                Label("Full guide (bootmod3 wiki)", systemImage: "book")
            }
        }
    }

    private func webSearchURL(for definition: TableDefinition) -> URL? {
        let terms = "\(model.displayName(definition)) BMW S58 MG1CS049 tune map"
        var components = URLComponents(string: "https://duckduckgo.com/")
        components?.queryItems = [URLQueryItem(name: "q", value: terms)]
        return components?.url
    }

    private func labeled(_ title: String, _ value: String) -> some View {
        LabeledContent(title, value: value)
    }
}
