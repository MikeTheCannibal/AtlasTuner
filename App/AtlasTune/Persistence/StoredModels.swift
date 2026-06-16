import Foundation
import SwiftData

/// SwiftData persistence layer. These mirror the engine's value types so the project library,
/// revision tree and saved logs survive relaunches and sync through CloudKit. The engine itself
/// (`AtlasTuneCore`) stays free of any persistence dependency.
///
/// All properties have defaults / are optional as CloudKit-backed SwiftData requires.

@Model
final class StoredProject {
    var id: UUID = UUID()
    var name: String = ""
    var family: String = ""
    var calibrationVersion: String = ""
    var definitionPackageID: String = ""
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()

    /// The current working image bytes.
    @Attribute(.externalStorage) var workingImageData: Data = Data()

    @Relationship(deleteRule: .cascade, inverse: \StoredRevision.project)
    var revisions: [StoredRevision]? = []

    @Relationship(deleteRule: .cascade, inverse: \StoredLogSession.project)
    var logSessions: [StoredLogSession]? = []

    init(id: UUID = UUID(), name: String, family: String, calibrationVersion: String,
         definitionPackageID: String, workingImageData: Data) {
        self.id = id
        self.name = name
        self.family = family
        self.calibrationVersion = calibrationVersion
        self.definitionPackageID = definitionPackageID
        self.workingImageData = workingImageData
        self.createdAt = Date()
        self.modifiedAt = Date()
    }
}

@Model
final class StoredRevision {
    var id: UUID = UUID()
    var parentID: UUID?
    var name: String = ""
    var notes: String = ""
    var timestamp: Date = Date()
    var checksum: Int = 0
    @Attribute(.externalStorage) var imageData: Data = Data()

    var project: StoredProject?

    init(id: UUID = UUID(), parentID: UUID? = nil, name: String, notes: String = "",
         timestamp: Date = Date(), checksum: Int = 0, imageData: Data) {
        self.id = id
        self.parentID = parentID
        self.name = name
        self.notes = notes
        self.timestamp = timestamp
        self.checksum = checksum
        self.imageData = imageData
    }
}

@Model
final class StoredLogSession {
    var id: UUID = UUID()
    var name: String = ""
    var startedAt: Date = Date()
    /// JSON-encoded `LogSession` payload from the engine.
    @Attribute(.externalStorage) var payload: Data = Data()

    var project: StoredProject?

    init(id: UUID = UUID(), name: String, startedAt: Date = Date(), payload: Data) {
        self.id = id
        self.name = name
        self.startedAt = startedAt
        self.payload = payload
    }
}
