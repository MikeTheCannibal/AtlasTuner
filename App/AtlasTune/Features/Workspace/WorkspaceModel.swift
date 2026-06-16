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

    let catalog: DefinitionCatalog

    init(catalog: DefinitionCatalog = .phase1) {
        self.catalog = catalog
    }

    var identity: ROMIdentity? { project?.identity }
    var package: DefinitionPackage? { project?.package }
    var canUndo: Bool { project?.canUndo ?? false }
    var canRedo: Bool { project?.canRedo ?? false }

    // MARK: Import

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
        refreshSearch()
    }

    // MARK: Tables

    func openTable(id: String) {
        guard let project else { return }
        openTableID = id
        openTable = try? project.table(id: id)
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
