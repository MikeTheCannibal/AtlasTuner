import Foundation

/// Manages the parent/child relationships between ``Revision``s for one calibration project.
/// Supports branching histories (e.g. a "Track" branch diverging from "Revision 2").
public struct RevisionTree: Codable, Sendable {
    public private(set) var revisions: [UUID: Revision]
    /// Insertion order, used for stable listing.
    public private(set) var order: [UUID]

    public init(revisions: [Revision] = []) {
        self.revisions = Dictionary(uniqueKeysWithValues: revisions.map { ($0.id, $0) })
        self.order = revisions.map(\.id)
    }

    @discardableResult
    public mutating func add(_ revision: Revision) -> Revision {
        if revisions[revision.id] == nil { order.append(revision.id) }
        revisions[revision.id] = revision
        return revision
    }

    public func revision(_ id: UUID) -> Revision? { revisions[id] }

    /// The root revisions (no parent), typically the imported "Stock".
    public var roots: [Revision] {
        order.compactMap { revisions[$0] }.filter { $0.parentID == nil }
    }

    public func children(of id: UUID) -> [Revision] {
        order.compactMap { revisions[$0] }.filter { $0.parentID == id }
    }

    /// The chain from a root down to `id`, ancestors first.
    public func lineage(of id: UUID) -> [Revision] {
        var chain: [Revision] = []
        var cursor: UUID? = id
        while let current = cursor, let rev = revisions[current] {
            chain.append(rev)
            cursor = rev.parentID
        }
        return chain.reversed()
    }

    public var all: [Revision] { order.compactMap { revisions[$0] } }
}
