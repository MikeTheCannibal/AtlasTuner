import Foundation
import Observation
import AtlasTuneCore

/// The main-actor view model for one calibration workspace. It owns the engine
/// `CalibrationProject` and republishes the slices SwiftUI needs. All heavy work (identification,
/// reads, edits) is delegated to the `Sendable` engine and can be hopped off the main actor.
@MainActor
@Observable
final class WorkspaceModel {
    enum State {
        case empty
        case identifying
        case ready
        case unrecognized
    }

    private(set) var state: State = .empty
    private(set) var project: CalibrationProject?

    /// Currently open table (engineering values) for the editor.
    private(set) var openTable: CalibrationTable?
    var openTableID: String?

    var searchQuery: String = ""
    private(set) var searchResults: [TableSearchResult] = []

    /// Table IDs the tuner starred, persisted per package so they survive relaunch.
    private(set) var favorites: Set<String> = []
    /// Most-recently opened table IDs, newest first (session-only).
    private(set) var recents: [String] = []
    private let maxRecents = 8

    let catalog: DefinitionCatalog

    init(catalog: DefinitionCatalog = .phase1) {
        self.catalog = catalog
    }

    var identity: ROMIdentity? { project?.identity }
    var package: DefinitionPackage? { project?.package }
    var canUndo: Bool { project?.canUndo ?? false }
    var canRedo: Bool { project?.canRedo ?? false }

    // MARK: Import

    /// Open a bundled synthetic S58 image so the app can be explored without a real dump — useful
    /// on the Simulator and for onboarding/demo, where no BIN can be side-loaded.
    func openSample() async {
        state = .identifying
        let opened = await Task.detached(priority: .userInitiated) {
            CalibrationProject.open(image: SampleImage.s58())
        }.value
        guard let opened else { state = .unrecognized; return }
        project = opened
        state = .ready
        recents = []
        loadFavorites()
        refreshSearch()
    }

    /// Identify and open imported BIN bytes. Identification runs off the main actor.
    func importImage(_ data: Data) async {
        state = .identifying
        let catalog = self.catalog
        let opened = await Task.detached(priority: .userInitiated) {
            CalibrationProject.open(image: BINImage(bytes: data), catalog: catalog)
        }.value

        guard let opened else {
            state = .unrecognized
            return
        }
        project = opened
        state = .ready
        recents = []
        loadFavorites()
        refreshSearch()
    }

    // MARK: Tables

    func openTable(id: String) {
        guard let project else { return }
        openTableID = id
        openTable = try? project.table(id: id)
        recents.removeAll { $0 == id }
        recents.insert(id, at: 0)
        if recents.count > maxRecents { recents.removeLast(recents.count - maxRecents) }
    }

    // MARK: Favorites

    func isFavorite(_ id: String) -> Bool { favorites.contains(id) }

    func toggleFavorite(_ id: String) {
        if favorites.contains(id) { favorites.remove(id) } else { favorites.insert(id) }
        persistFavorites()
    }

    /// Favorited tables, resolved against the current package (skips ids not in this package).
    func favoriteTables() -> [TableDefinition] {
        guard let package else { return [] }
        return package.tables.filter { favorites.contains($0.id) }
    }

    /// Recently opened tables, newest first.
    func recentTables() -> [TableDefinition] {
        guard let package else { return [] }
        return recents.compactMap { id in package.tables.first { $0.id == id } }
    }

    private var favoritesKey: String { "favorites.\(package?.id ?? "unknown")" }

    private func persistFavorites() {
        UserDefaults.standard.set(Array(favorites), forKey: favoritesKey)
    }

    private func loadFavorites() {
        favorites = Set(UserDefaults.standard.stringArray(forKey: favoritesKey) ?? [])
    }

    /// Apply an edit to the open table, updating the working image and undo history.
    func applyEdit(_ operation: EditOperation, region: CellRegion) {
        guard var project, let tableID = openTableID else { return }
        openTable = try? project.applyEdit(operation, region: region, toTableID: tableID)
        self.project = project
    }

    func undo() {
        guard var project else { return }
        if project.undo(), let id = openTableID { openTable = try? project.table(id: id) }
        self.project = project
    }

    func redo() {
        guard var project else { return }
        if project.redo(), let id = openTableID { openTable = try? project.table(id: id) }
        self.project = project
    }

    // MARK: Revisions

    @discardableResult
    func saveRevision(name: String, notes: String = "") -> Revision? {
        guard var project else { return nil }
        let rev = project.saveRevision(name: name, notes: notes)
        self.project = project
        return rev
    }

    // MARK: Search

    func refreshSearch() {
        searchResults = project?.search(searchQuery) ?? []
    }

    func tables(in category: CalibrationCategory) -> [TableDefinition] {
        package?.tables(in: category) ?? []
    }

    func validate() -> ValidationReport? {
        project?.validate()
    }
}
