import SwiftUI
import AtlasTuneCore

/// The left navigator: instant search plus Favorites and Recent shortcuts above collapsible
/// functional folders (Boost, Fuel, Ignition, …), so the tuner reaches a map in one tap instead of
/// hunting 1370 tables. Tapping a row opens the map; the star (or right-click ▸ Pin) toggles a
/// favorite. Names are shown in English when translation is on.
struct CategoryNavigatorView: View {
    @Bindable var model: WorkspaceModel

    var body: some View {
        List(selection: Binding(get: { model.openTableID }, set: { if let id = $0 { model.openTable(id: id) } })) {
            if model.searchQuery.isEmpty {
                let favorites = model.favoriteTables()
                if !favorites.isEmpty {
                    Section("★ Favorites") {
                        ForEach(favorites) { tableRow($0) }
                    }
                }
                let recents = model.recentTables()
                if !recents.isEmpty {
                    Section("Recent") {
                        ForEach(recents) { tableRow($0) }
                    }
                }
                ForEach(model.subcategoryGroups(), id: \.name) { group in
                    Section(model.displaySubcategory(group.name)) {
                        ForEach(group.tables) { tableRow($0) }
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
                Text(model.displayName(table))
                    .lineLimit(2)
                Spacer(minLength: 4)
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
        .contextMenu {
            Button {
                model.toggleFavorite(table.id)
            } label: {
                Label(model.isFavorite(table.id) ? "Unpin from Favorites" : "Pin to Favorites",
                      systemImage: model.isFavorite(table.id) ? "star.slash" : "star")
            }
            Button {
                model.openTable(id: table.id)
            } label: {
                Label("Open", systemImage: "arrow.up.right.square")
            }
        }
    }
}
