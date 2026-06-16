import Foundation

/// The engine-side aggregate for one open calibration. It owns the working image, undo history,
/// revision tree and definition package, and exposes the high-level operations the SwiftUI
/// view models drive. Pure Swift and `Sendable`, so it can run off the main actor.
public struct CalibrationProject: Sendable {
    public let identity: ROMIdentity
    public let package: DefinitionPackage

    /// Undo/redo history of the full working image.
    private var history: UndoStack<BINImage>
    public private(set) var revisions: RevisionTree

    private let accessor = TableAccessor()
    private let editEngine = EditEngine()
    public let searchIndex: TableSearchIndex

    /// The current, possibly-unsaved working image.
    public var workingImage: BINImage { history.current }

    // MARK: Lifecycle

    /// Open a project from an identified image. The initial state is captured as a "Stock" root
    /// revision, satisfying the "automatic backup before edits" safety requirement.
    public init(image: BINImage, identity: ROMIdentity, package: DefinitionPackage) {
        self.identity = identity
        self.package = package
        self.history = UndoStack(initial: image)
        self.searchIndex = TableSearchIndex(package: package)
        var tree = RevisionTree()
        tree.add(Revision(name: "Stock", notes: "Imported calibration", image: image))
        self.revisions = tree
    }

    /// Identify and open an image against a catalog. Returns `nil` if unrecognised.
    public static func open(image: BINImage, catalog: DefinitionCatalog = .phase1) -> CalibrationProject? {
        guard let match = catalog.identify(image) else { return nil }
        return CalibrationProject(image: image, identity: match.identity, package: match.package)
    }

    // MARK: Tables

    public func table(id: String) throws -> CalibrationTable? {
        guard let definition = package.table(id: id) else { return nil }
        return try accessor.read(definition, from: workingImage)
    }

    /// Apply an edit to a region of a table, writing it back to the working image and committing
    /// the change to the undo history. Returns the updated table.
    @discardableResult
    public mutating func applyEdit(
        _ operation: EditOperation,
        region: CellRegion,
        toTableID tableID: String
    ) throws -> CalibrationTable? {
        guard let table = try table(id: tableID) else { return nil }
        let edited = editEngine.apply(operation, to: table, region: region)
        let updatedImage = try accessor.write(edited, into: workingImage)
        history.commit(updatedImage)
        return edited
    }

    // MARK: Undo / redo

    public var canUndo: Bool { history.canUndo }
    public var canRedo: Bool { history.canRedo }

    @discardableResult public mutating func undo() -> Bool { history.undo() != nil }
    @discardableResult public mutating func redo() -> Bool { history.redo() != nil }

    // MARK: Revisions

    /// Snapshot the current working image as a new revision branching from `parentID`
    /// (defaults to the most recent revision).
    @discardableResult
    public mutating func saveRevision(name: String, notes: String = "", parentID: UUID? = nil) -> Revision {
        let parent = parentID ?? revisions.all.last?.id
        let revision = Revision(parentID: parent, name: name, notes: notes, image: workingImage)
        revisions.add(revision)
        return revision
    }

    public func difference(from a: UUID, to b: UUID, tolerance: Double = 1e-6) -> CalibrationDifference? {
        guard let before = revisions.revision(a)?.image,
              let after = revisions.revision(b)?.image else { return nil }
        return DifferenceEngine(tolerance: tolerance).compare(before, after, using: package)
    }

    /// Difference between the current working image and a revision.
    public func differenceFromWorking(to revisionID: UUID, tolerance: Double = 1e-6) -> CalibrationDifference? {
        guard let other = revisions.revision(revisionID)?.image else { return nil }
        return DifferenceEngine(tolerance: tolerance).compare(other, workingImage, using: package)
    }

    // MARK: Search & validation

    public func search(_ query: String) -> [TableSearchResult] {
        searchIndex.search(query)
    }

    public func validate() -> ValidationReport {
        ExportValidator().validate(workingImage, using: package)
    }
}
