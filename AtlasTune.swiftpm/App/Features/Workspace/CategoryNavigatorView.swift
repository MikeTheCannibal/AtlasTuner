import SwiftUI
import AtlasTuneCore

/// The left navigator: a two-level collapsible tree (category → subcategory → tables) so a tuner
/// can drill straight to, say, a Fuel table without scrolling past everything. Names wrap so they
/// are fully readable, and are auto-translated from German when translation is enabled. Search
/// flattens to a live result list.
struct CategoryNavigatorView: View {
    @Bindable var model: WorkspaceModel

    @State private var expandedCategories: Set<CalibrationCategory> = []
    @State private var expandedSubcategories: Set<String> = []

    var body: some View {
        List {
            if model.searchQuery.isEmpty {
                ForEach(model.package?.categories ?? [], id: \.self) { category in
                    categorySection(category)
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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Expand All") { expandAll() }
                    Button("Collapse All") { expandedCategories.removeAll(); expandedSubcategories.removeAll() }
                } label: { Image(systemName: "list.bullet.indent") }
            }
        }
    }

    // MARK: Tree

    private func categorySection(_ category: CalibrationCategory) -> some View {
        DisclosureGroup(isExpanded: categoryBinding(category)) {
            ForEach(model.subcategories(in: category), id: \.self) { sub in
                subcategoryGroup(category, sub)
            }
        } label: {
            Label {
                HStack {
                    Text(category.displayName).font(.headline)
                    Spacer()
                    Text("\(model.tables(in: category).count)")
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: category.symbolName).foregroundStyle(.tint)
            }
        }
    }

    private func subcategoryGroup(_ category: CalibrationCategory, _ sub: String) -> some View {
        let tables = model.tables(in: category, subcategory: sub)
        return DisclosureGroup(isExpanded: subcategoryBinding(category, sub)) {
            ForEach(tables) { tableRow($0) }
        } label: {
            HStack {
                Text(model.displaySubcategory(sub)).font(.subheadline)
                Spacer()
                Text("\(tables.count)").font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
            }
        }
    }

    private func tableRow(_ table: TableDefinition) -> some View {
        Button {
            model.openTable(id: table.id)
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "tablecells")
                    .font(.caption)
                    .foregroundStyle(model.openTableID == table.id ? Color.accentColor : .secondary)
                    .padding(.top, 2)
                Text(model.displayName(table))
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true) // wrap to read fully
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(model.openTableID == table.id ? Color.accentColor.opacity(0.15) : nil)
    }

    // MARK: Expansion bindings

    private func categoryBinding(_ category: CalibrationCategory) -> Binding<Bool> {
        Binding(
            get: { expandedCategories.contains(category) },
            set: { isOpen in
                if isOpen { expandedCategories.insert(category) }
                else { expandedCategories.remove(category) }
            }
        )
    }

    private func subcategoryBinding(_ category: CalibrationCategory, _ sub: String) -> Binding<Bool> {
        let key = "\(category.rawValue)|\(sub)"
        return Binding(
            get: { expandedSubcategories.contains(key) },
            set: { isOpen in
                if isOpen { expandedSubcategories.insert(key) }
                else { expandedSubcategories.remove(key) }
            }
        )
    }

    private func expandAll() {
        for category in model.package?.categories ?? [] {
            expandedCategories.insert(category)
            for sub in model.subcategories(in: category) {
                expandedSubcategories.insert("\(category.rawValue)|\(sub)")
            }
        }
    }
}
