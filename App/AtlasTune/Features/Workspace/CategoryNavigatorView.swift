import SwiftUI
import AtlasTuneCore

/// The left navigator: instant search, ★ Favorites and Recent pinned on top, then **collapsed
/// drill-down folders** per functional area (Boost, Fuel, Ignition, …) so the tuner is never
/// staring at 1370 rows at once — expand only the area being worked. Tapping a row opens the map;
/// the star (or right-click ▸ Pin) toggles a favorite. Names show in English when translation is on.
struct CategoryNavigatorView: View {
    @Bindable var model: WorkspaceModel
    /// Folders the tuner has expanded (session state; all folders start collapsed).
    @State private var expandedFolders: Set<String> = []

    var body: some View {
        List(selection: selectionBinding) {
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
                Section("Maps") {
                    ForEach(model.subcategoryGroups(), id: \.name) { group in
                        folder(group.name, tables: group.tables)
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

    /// Defer the open to the next runloop tick: mutating model state synchronously inside the
    /// selection setter triggers AppKit's reentrant-NSTableView warning on macOS.
    private var selectionBinding: Binding<String?> {
        Binding(get: { model.openTableID },
                set: { id in
                    guard let id else { return }
                    Task { @MainActor in model.openTable(id: id) }
                })
    }

    /// One collapsible functional folder with a map count, collapsed by default.
    private func folder(_ name: String, tables: [TableDefinition]) -> some View {
        DisclosureGroup(isExpanded: expansionBinding(name)) {
            ForEach(tables) { tableRow($0) }
        } label: {
            HStack {
                Label(model.displaySubcategory(name), systemImage: "folder")
                Spacer(minLength: 4)
                Text("\(tables.count)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(Color.secondaryBackground, in: Capsule())
            }
        }
    }

    private func expansionBinding(_ name: String) -> Binding<Bool> {
        Binding(get: { expandedFolders.contains(name) },
                set: { expanded in
                    if expanded { expandedFolders.insert(name) } else { expandedFolders.remove(name) }
                })
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
