import Foundation

/// A ranked search result over the table catalogue.
public struct TableSearchResult: Sendable, Identifiable, Equatable {
    public let table: TableDefinition
    public let score: Int
    public var id: String { table.id }
}

/// A small in-memory index that supports instant search across table name, category,
/// description and axis names. Built once per loaded package; queries are O(n) over a few
/// hundred tables, which is comfortably instantaneous.
public struct TableSearchIndex: Sendable {
    private struct Entry: Sendable {
        let table: TableDefinition
        let haystack: String
        let name: String
        let category: String
        let axes: String
    }

    private let entries: [Entry]

    public init(package: DefinitionPackage) {
        self.entries = package.tables.map { table in
            let axes = [table.xAxis?.name, table.yAxis?.name].compactMap { $0 }.joined(separator: " ")
            let haystack = [table.name, table.category.displayName, table.subcategory ?? "", table.description, axes]
                .joined(separator: " ")
                .lowercased()
            return Entry(
                table: table,
                haystack: haystack,
                name: table.name.lowercased(),
                category: table.category.displayName.lowercased(),
                axes: axes.lowercased()
            )
        }
    }

    /// Search for `query`, returning matches ranked by relevance (name hits rank highest).
    public func search(_ query: String) -> [TableSearchResult] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else {
            return entries.map { TableSearchResult(table: $0.table, score: 0) }
                .sorted { $0.table.name < $1.table.name }
        }
        let terms = needle.split(separator: " ").map(String.init)

        var results: [TableSearchResult] = []
        for entry in entries {
            var score = 0
            for term in terms {
                guard entry.haystack.contains(term) else { score = .min; break }
                if entry.name == term { score += 100 }
                else if entry.name.hasPrefix(term) { score += 50 }
                else if entry.name.contains(term) { score += 25 }
                if entry.category.contains(term) { score += 10 }
                if entry.axes.contains(term) { score += 5 }
                score += 1
            }
            if score > .min {
                results.append(TableSearchResult(table: entry.table, score: score))
            }
        }
        return results.sorted { $0.score != $1.score ? $0.score > $1.score : $0.table.name < $1.table.name }
    }
}
