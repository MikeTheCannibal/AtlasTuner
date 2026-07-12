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

    /// Translate German Bosch/BMW map names to English for display. Persisted globally.
    var translateNames: Bool {
        didSet { UserDefaults.standard.set(translateNames, forKey: "translateNames") }
    }

    let catalog: DefinitionCatalog
    private let translator = MapNameTranslator()
    private var translationCache: [String: String] = [:]

    init(catalog: DefinitionCatalog = .phase1) {
        self.catalog = catalog
        self.translateNames = UserDefaults.standard.object(forKey: "translateNames") as? Bool ?? true
    }

    // MARK: Display names (German → English)

    /// The name to show for a table, honoring the translate-names setting (cached).
    func displayName(_ definition: TableDefinition) -> String {
        guard translateNames else { return definition.name }
        if let cached = translationCache[definition.name] { return cached }
        let translated = translator.translate(definition.name)
        translationCache[definition.name] = translated
        return translated
    }

    func displaySubcategory(_ raw: String) -> String {
        guard translateNames else { return raw }
        if let cached = translationCache[raw] { return cached }
        let translated = translator.translate(raw)
        translationCache[raw] = translated
        return translated
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
        loadFavorites()
        loadZoom()
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
        loadFavorites()
        loadZoom()
        refreshSearch()
    }

    // MARK: Tables

    func openTable(id: String) {
        guard let project else { return }
        openTableID = id
        openTable = try? project.table(id: id)
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

    private var favoritesKey: String { "favorites.\(package?.id ?? "unknown")" }

    private func persistFavorites() {
        UserDefaults.standard.set(Array(favorites), forKey: favoritesKey)
    }

    private func loadFavorites() {
        favorites = Set(UserDefaults.standard.stringArray(forKey: favoritesKey) ?? [])
    }

    // MARK: Per-map zoom (persisted like favorites: per package, survives relaunch)

    /// Spreadsheet zoom per table id. Only non-default zooms are stored.
    private(set) var zoomByTable: [String: Double] = [:]

    func zoom(for tableID: String) -> Double {
        zoomByTable[tableID] ?? 1.0
    }

    func setZoom(_ zoom: Double, for tableID: String) {
        if abs(zoom - 1.0) < 0.01 {
            zoomByTable.removeValue(forKey: tableID)      // default: don't store noise
        } else {
            zoomByTable[tableID] = zoom
        }
        UserDefaults.standard.set(zoomByTable, forKey: zoomKey)
    }

    private var zoomKey: String { "zoom.\(package?.id ?? "unknown")" }

    private func loadZoom() {
        zoomByTable = (UserDefaults.standard.dictionary(forKey: zoomKey) as? [String: Double]) ?? [:]
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
        guard let package else { searchResults = []; return }
        let engineHits = project?.search(searchQuery) ?? []
        guard translateNames, !searchQuery.isEmpty else { searchResults = engineHits; return }
        // With translation on, also match the English display name so an English query finds a
        // German-named map. Merge with engine hits, engine hits first, de-duplicated.
        let q = searchQuery.lowercased()
        var seen = Set(engineHits.map(\.table.id))
        var merged = engineHits
        for table in package.tables where !seen.contains(table.id) && displayName(table).lowercased().contains(q) {
            merged.append(TableSearchResult(table: table, score: 0))
            seen.insert(table.id)
        }
        searchResults = merged
    }

    func tables(in category: CalibrationCategory) -> [TableDefinition] {
        package?.tables(in: category) ?? []
    }

    /// Functional folders for the navigator, bm3-style: tables grouped by their subcategory,
    /// with the common tuning areas ordered first and the big catch-alls last.
    func subcategoryGroups() -> [(name: String, tables: [TableDefinition])] {
        guard let package else { return [] }
        var groups: [String: [TableDefinition]] = [:]
        for table in package.tables {
            groups[table.subcategory ?? "Other", default: []].append(table)
        }
        let priority = ["Boost", "WGDC", "Fuel", "Ignition", "Limits", "Torque request",
                        "Load", "Throttle", "Vanos", "Cooling", "Idle", "MAF", "Exhaust",
                        "Rev limits", "Sensor Calibrations", "Oil Pressure"]
        func rank(_ name: String) -> Int { priority.firstIndex(of: name) ?? priority.count }
        return groups
            .map { (name: $0.key, tables: $0.value.sorted { $0.name < $1.name }) }
            .sorted { lhs, rhs in
                let (a, b) = (rank(lhs.name), rank(rhs.name))
                return a != b ? a < b : lhs.name < rhs.name
            }
    }

    func validate() -> ValidationReport? {
        project?.validate()
    }
}
