import Foundation
import SwiftData
import AtlasTuneCore

/// Bridges the engine's `CalibrationProject` / `Revision` value types to SwiftData models.
/// Keeping the mapping here means the rest of the app talks to the engine, not the database.
@MainActor
struct ProjectStore {
    let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    /// Persist a freshly opened or edited project, replacing any existing record with the same id.
    func save(_ project: CalibrationProject, name: String, id: UUID = UUID()) throws {
        let stored = StoredProject(
            id: id,
            name: name,
            family: project.identity.family,
            calibrationVersion: project.identity.calibrationVersion,
            definitionPackageID: project.package.id,
            workingImageData: project.workingImage.bytes
        )
        stored.modifiedAt = Date()
        stored.revisions = project.revisions.all.map { rev in
            StoredRevision(
                id: rev.id, parentID: rev.parentID, name: rev.name, notes: rev.notes,
                timestamp: rev.timestamp, checksum: Int(rev.checksum), imageData: rev.imageData
            )
        }
        context.insert(stored)
        try context.save()
    }

    /// Rebuild an engine `RevisionTree` from a stored project.
    func revisionTree(from stored: StoredProject) -> RevisionTree {
        let revisions = (stored.revisions ?? [])
            .sorted { $0.timestamp < $1.timestamp }
            .map { s in
                Revision(
                    id: s.id, parentID: s.parentID, name: s.name, notes: s.notes,
                    timestamp: s.timestamp,
                    image: BINImage(bytes: s.imageData, byteOrder: .littleEndian)
                )
            }
        return RevisionTree(revisions: revisions)
    }
}
