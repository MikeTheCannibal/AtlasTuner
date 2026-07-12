import SwiftUI
import AtlasTuneCore

/// The left navigator: instant search plus Favorites and Recent shortcuts above the category-grouped
/// table list, so the tuner reaches a map in one tap instead of hunting 1370 tables. Tapping a row
/// opens the map; the star toggles a favorite.
struct CategoryNavigatorView: View {
    @Bindable var model: WorkspaceModel

    var body: some View {
        List(selection: Binding(get: { model.openTableID }, set: { if let id = $0 { model.openTable(id: id) } })) {
            if model.searchQuery.isEmpty {
                let favorites = model.favoriteTables()
                if !favorites.isEmpty {
                    Section("Favorites") {
                        ForEach(favorites) { tableRow($0) }
                    }
                }
                let recents = model.recentTables()
                if !recents.isEmpty {
                    Section("Recent") {
                        ForEach(recents) { tableRow($0) }
                    }
                }
                ForEach(model.package?.categories ?? [], id: \.self) { category in
                    Section(category.displayName) {
                        ForEach(model.tables(in: category)) { tableRow($0) }
                    }
                }
            } else {
                Section("Results") {
                    ForEach(model.searchResults) { tableRow($0.table) }
                }
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $model.searchQuery, placement: .sidebar, prompt: "Search maps")
        .onChange(of: model.searchQuery) { _, _ in model.refreshSearch() }
    }

    private func tableRow(_ table: TableDefinition) -> some View {
        Label {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(table.name)
                    if let sub = table.subcategory {
                        Text(sub).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button {
                    model.toggleFavorite(table.id)
                } label: {
                    Image(systemName: model.isFavorite(table.id) ? "star.fill" : "star")
                        .foregroundStyle(model.isFavorite(table.id) ? .yellow : .secondary)
                }
                .buttonStyle(.plain)
                .help(model.isFavorite(table.id) ? "Remove favorite" : "Add favorite")
            }
        } icon: {
            Image(systemName: table.category.symbolName)
                .foregroundStyle(.tint)
        }
        .tag(table.id)
    }
}
