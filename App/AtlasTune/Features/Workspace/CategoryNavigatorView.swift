import SwiftUI
import AtlasTuneCore

/// The left navigator: an instant search field over a category-grouped table list. Tapping a
/// table opens it in the editor. Search and browse share the same list so results appear live.
struct CategoryNavigatorView: View {
    @Bindable var model: WorkspaceModel

    var body: some View {
        List(selection: Binding(get: { model.openTableID }, set: { if let id = $0 { model.openTable(id: id) } })) {
            if model.searchQuery.isEmpty {
                ForEach(model.package?.categories ?? [], id: \.self) { category in
                    Section(category.displayName) {
                        ForEach(model.tables(in: category)) { table in
                            tableRow(table)
                        }
                    }
                }
            } else {
                Section("Results") {
                    ForEach(model.searchResults) { result in
                        tableRow(result.table)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $model.searchQuery, placement: .sidebar, prompt: "Search tables")
        .onChange(of: model.searchQuery) { _, _ in model.refreshSearch() }
    }

    private func tableRow(_ table: TableDefinition) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(table.name)
                if let sub = table.subcategory {
                    Text(sub).font(.caption).foregroundStyle(.secondary)
                }
            }
        } icon: {
            Image(systemName: table.category.symbolName)
                .foregroundStyle(.tint)
        }
        .tag(table.id)
    }
}
